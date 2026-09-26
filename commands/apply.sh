#!/bin/sh
# commands/apply.sh - Apply lxc.json changes to existing container

cmd_apply() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"
    . "$PVC_LIB/lib/tags.sh"
    . "$PVC_LIB/lib/mount.sh"

    config_require_jq
    config_load_lxc_json || die "No lxc.json found"
    config_load_global || true

    _ctid=$(config_get_ctid)
    [ -n "$_ctid" ] || die "No CTID in lxc.json"
    lxc_exists "$_ctid" || die "Container $_ctid does not exist"

    _conf="/etc/pve/lxc/${_ctid}.conf"

    # ── Read desired state from lxc.json ──
    # shellcheck disable=SC2154
    _want_hostname=$(printf '%s' "$_lxc_json" | jq -r '.hostname // empty')
    [ -z "$_want_hostname" ] && _want_hostname=$(basename "$(pwd)")
    _want_cores=$(printf '%s' "$_lxc_json" | jq -r '.cores // empty')
    _want_memory=$(printf '%s' "$_lxc_json" | jq -r '.memory // empty')
    _want_swap=$(config_get_field "swap" "")
    _want_ipv4=$(printf '%s' "$_lxc_json" | jq -r '.ipv4 // empty')
    _want_gateway=$(printf '%s' "$_lxc_json" | jq -r '.gateway // empty')
    _want_dns=$(printf '%s' "$_lxc_json" | jq -r '.dns // empty')
    _want_bridge=$(printf '%s' "$_lxc_json" | jq -r '.bridge // empty')
    _want_disk=$(printf '%s' "$_lxc_json" | jq -r '.disk // empty')
    _want_storage=$(printf '%s' "$_lxc_json" | jq -r '.storage // empty')
    _want_template=$(printf '%s' "$_lxc_json" | jq -r '.template // empty')
    _want_mnt_src=$(printf '%s' "$_lxc_json" | jq -r '.mount.source // empty')
    _want_mnt_tgt=$(printf '%s' "$_lxc_json" | jq -r '.mount.target // empty')

    # Validate numeric fields up front with a readable error
    [ -n "$_want_cores" ]  && config_require_uint "$_want_cores"  "cores"
    [ -n "$_want_memory" ] && config_require_uint "$_want_memory" "memory"
    [ -n "$_want_swap" ]   && config_require_uint "$_want_swap"   "swap"

    # Features: honour the `features` field if present, otherwise derive from
    # `privileged`. Always normalized (sorted) so comparison is stable.
    _feat_json=$(printf '%s' "$_lxc_json" | jq -c '.features // empty' 2>/dev/null)
    if [ -n "$_feat_json" ]; then
        _want_features=$(config_features_to_string "$_feat_json")
    else
        _priv=$(printf '%s' "$_lxc_json" | jq -r '.privileged // "true"')
        if [ "$_priv" = "false" ]; then
            _want_features="keyctl=1,nesting=1"
        else
            _want_features="nesting=1"
        fi
    fi
    _want_features=$(config_features_normalize "$_want_features")

    # Tags - expand templates
    _tags_raw=""
    _tags_type=$(printf '%s' "$_lxc_json" | jq -r '.tags | type // "null"' 2>/dev/null)
    case "$_tags_type" in
        array)  _tags_raw=$(printf '%s' "$_lxc_json" | jq -r '.tags | join(";")' 2>/dev/null) ;;
        string) _tags_raw=$(printf '%s' "$_lxc_json" | jq -r '.tags // empty' 2>/dev/null) ;;
    esac
    if [ -n "$_tags_raw" ]; then
        # Build minimal JSON for tag expansion
        _mini_json=$(jq -n --arg h "$_want_hostname" --arg ip "$_want_ipv4" \
            '{hostname: $h, ipv4: $ip}')
        _want_tags=$(tags_expand "$_tags_raw" "$_mini_json")
    else
        _want_tags=""
    fi

    # ── Read current state from .conf ──
    _cur_hostname=$(sed -n 's/^hostname: *//p' "$_conf")
    _cur_cores=$(sed -n 's/^cores: *//p' "$_conf")
    _cur_memory=$(sed -n 's/^memory: *//p' "$_conf")
    _cur_swap=$(sed -n 's/^swap: *//p' "$_conf")
    _cur_dns=$(sed -n 's/^nameserver: *//p' "$_conf")
    _cur_features=$(config_features_normalize "$(sed -n 's/^features: *//p' "$_conf")")
    _cur_tags=$(sed -n 's/^tags: *//p' "$_conf")

    # rootfs line: "rootfs: local-zfs:subvol-101-disk-0,size=8G"
    _rootfs_line=$(sed -n 's/^rootfs: *//p' "$_conf")
    _cur_storage=$(printf '%s' "$_rootfs_line" | sed -n 's/^\([^:]*\):.*/\1/p')
    _cur_disk=$(printf '%s' "$_rootfs_line" | sed -n 's/.*size=\([0-9]*\)[gG].*/\1/p')

    # Parse net0 (composite)
    _net0_line=$(sed -n 's/^net0: *//p' "$_conf")
    _cur_ip="" _cur_gw="" _cur_bridge=""
    if [ -n "$_net0_line" ]; then
        _old_ifs="$IFS"; IFS=","
        for _kv in $_net0_line; do
            case "$_kv" in
                ip=*)     _cur_ip="${_kv#ip=}" ;;
                gw=*)     _cur_gw="${_kv#gw=}" ;;
                bridge=*) _cur_bridge="${_kv#bridge=}" ;;
            esac
        done
        IFS="$_old_ifs"
    fi

    # ── Immutable fields: warn instead of silently ignoring ──
    # storage and template cannot change on an existing container.
    if [ -n "$_want_storage" ] && [ -n "$_cur_storage" ] && [ "$_want_storage" != "$_cur_storage" ]; then
        warn "storage: '$_cur_storage' -> '$_want_storage' cannot be changed on an existing container."
        warn "  To move it: pct stop $_ctid && pct move-volume $_ctid rootfs $_want_storage"
    fi
    if [ -n "$_want_template" ]; then
        _tmpl_marker="$PVC_STATE_DIR/template"
        if [ -f "$_tmpl_marker" ]; then
            _cur_template=$(cat "$_tmpl_marker" 2>/dev/null)
            if [ -n "$_cur_template" ] && [ "$_cur_template" != "$_want_template" ]; then
                warn "template: '$_cur_template' -> '$_want_template' only applies when recreating the container."
            fi
        fi
    fi

    # ── Disk resize (BUGFIX: was silently ignored) ──
    # ZFS/LVM can only grow a rootfs. Shrinking must fail loudly.
    _disk_grow=""
    if [ -n "$_want_disk" ]; then
        _want_disk_gb=$(config_normalize_disk "$_want_disk")
        if [ -n "$_cur_disk" ] && [ "$_want_disk_gb" != "$_cur_disk" ]; then
            if [ "$_want_disk_gb" -lt "$_cur_disk" ]; then
                warn "disk: ${_cur_disk}G -> ${_want_disk_gb}G is a SHRINK and cannot be done online."
                warn "  Proxmox does not support shrinking rootfs. Restore from backup into a smaller CT instead."
            else
                _disk_grow="$_want_disk_gb"
            fi
        fi
    fi

    # ── Bind mount (BUGFIX: was silently ignored) ──
    _mnt_changed=0
    if [ -n "$_want_mnt_src" ] || [ -n "$_want_mnt_tgt" ]; then
        _msrc="${_want_mnt_src:-$(pwd)}"
        _mtgt="${_want_mnt_tgt:-/data}"
        # find whether this source is already mounted, and where
        _cur_mp_line=$(grep -F ": ${_msrc}," "$_conf" 2>/dev/null | grep '^mp[0-9]' | head -1)
        if [ -z "$_cur_mp_line" ]; then
            _mnt_changed=1
            _mnt_desc=" mount: (none) -> $_msrc => $_mtgt;"
        else
            _cur_mtgt=$(printf '%s' "$_cur_mp_line" | sed -n 's/.*mp=\([^,]*\).*/\1/p')
            if [ "$_cur_mtgt" != "$_mtgt" ]; then
                _mnt_changed=1
                _mnt_desc=" mount target: $_cur_mtgt -> $_mtgt;"
            fi
        fi
    fi

    # ── Calculate diff ──
    _hot_args=""     # pct set args for hot-apply
    _restart_args="" # pct set args needing restart
    _hot_desc=""
    _restart_desc=""

    # Hot-apply fields
    _apply_field_hot() {
        _fname="$1" _fwant="$2" _fcur="$3" _flag="$4"
        [ -n "$_fwant" ] || return 0
        [ "$_fwant" != "$_fcur" ] || return 0
        _hot_args="$_hot_args $_flag $_fwant"
        _hot_desc="$_hot_desc $_fname: $_fcur -> $_fwant;"
    }

    _apply_field_hot "cores" "$_want_cores" "$_cur_cores" "--cores"
    _apply_field_hot "memory" "$_want_memory" "$_cur_memory" "--memory"
    _apply_field_hot "swap" "$_want_swap" "$_cur_swap" "--swap"
    _apply_field_hot "dns" "$_want_dns" "$_cur_dns" "--nameserver"
    _apply_field_hot "tags" "$_want_tags" "$_cur_tags" "--tags"

    # Restart-required fields
    _apply_field_restart() {
        _fname="$1" _fwant="$2" _fcur="$3" _flag="$4"
        [ -n "$_fwant" ] || return 0
        [ "$_fwant" != "$_fcur" ] || return 0
        _restart_args="$_restart_args $_flag $_fwant"
        _restart_desc="$_restart_desc $_fname: $_fcur -> $_fwant;"
    }

    _apply_field_restart "hostname" "$_want_hostname" "$_cur_hostname" "--hostname"
    _apply_field_restart "features" "$_want_features" "$_cur_features" "--features"

    # Network (composite - only if any part changed)
    _net_changed=0
    [ -n "$_want_ipv4" ] && [ "$_want_ipv4" != "$_cur_ip" ] && _net_changed=1
    [ -n "$_want_gateway" ] && [ "$_want_gateway" != "$_cur_gw" ] && _net_changed=1
    [ -n "$_want_bridge" ] && [ "$_want_bridge" != "$_cur_bridge" ] && _net_changed=1

    if [ "$_net_changed" = "1" ]; then
        _new_net0="name=eth0,bridge=${_want_bridge:-$_cur_bridge}"
        _nip="${_want_ipv4:-$_cur_ip}"
        if [ "$_nip" = "dhcp" ]; then
            _new_net0="$_new_net0,ip=dhcp"
        else
            _new_net0="$_new_net0,ip=$_nip"
            _ngw="${_want_gateway:-$_cur_gw}"
            [ -n "$_ngw" ] && _new_net0="$_new_net0,gw=$_ngw"
        fi
        _restart_args="$_restart_args --net0 $_new_net0"
        _restart_desc="$_restart_desc net0: $_cur_ip → $_nip;"
    fi

    # ── No changes? ──
    if [ -z "$_hot_args" ] && [ -z "$_restart_args" ] && [ -z "$_disk_grow" ] && [ "$_mnt_changed" != "1" ]; then
        info "No changes to apply."
        return 0
    fi

    # ── Apply hot fields (no restart) ──
    _applied=0
    if [ -n "$_hot_args" ]; then
        info "Hot-apply changes:$_hot_desc"
        # shellcheck disable=SC2086
        _pct_run set "$_ctid" $_hot_args
        _applied=1
    fi

    # ── Grow rootfs (online, no restart needed on ZFS/LVM-thin) ──
    if [ -n "$_disk_grow" ]; then
        _delta=$(( _disk_grow - _cur_disk ))
        info "Resizing rootfs: ${_cur_disk}G -> ${_disk_grow}G (+${_delta}G)"
        _pct_run resize "$_ctid" rootfs "+${_delta}G"
        _applied=1
    fi

    # ── Apply bind mount ──
    if [ "$_mnt_changed" = "1" ]; then
        info "Applying mount:$_mnt_desc"
        mount_configure "$_ctid" "$_msrc" "$_mtgt"
        _applied=1
    fi

    # ── Apply restart-required fields ──
    if [ -n "$_restart_args" ]; then
        warn "These changes require restart:$_restart_desc"
        if lxc_is_running "$_ctid"; then
            confirm "Restart container $_ctid now?" || {
                if [ "$_applied" = "1" ]; then
                    msg "Hot-apply changes applied. Restart pending for:$_restart_desc"
                else
                    info "No changes applied."
                fi
                return 0
            }
            step "Stopping container $_ctid..."
            _pct_run stop "$_ctid"
        fi
        # shellcheck disable=SC2086
        _pct_run set "$_ctid" $_restart_args
        step "Starting container $_ctid..."
        _pct_run start "$_ctid"
        lxc_wait_running "$_ctid" 100 || warn "Container may not be fully ready"
        _applied=1
    fi

    if [ "$_applied" = "1" ]; then
        msg "Changes applied to CT $_ctid"
    fi
}
