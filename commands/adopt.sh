#!/bin/sh
# commands/adopt.sh - Bring an existing LXC under pve-compose management
# Reads the real container config and writes a matching lxc.json.

cmd_adopt() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/resolve.sh"

    config_require_jq

    _force=0
    _ctid=""
    for _arg in "$@"; do
        case "$_arg" in
            --force|-f) _force=1 ;;
            -*) die "Unknown option for adopt: $_arg" ;;
            *)
                [ -z "$_ctid" ] || die "adopt takes a single CTID"
                config_require_uint "$_arg" "ctid"
                _ctid="$_arg"
                ;;
        esac
    done

    if [ -f "$PVC_LXC_JSON" ] && [ "$_force" != "1" ]; then
        _have=$(jq -r '.ctid // "?"' "$PVC_LXC_JSON" 2>/dev/null)
        die "lxc.json already exists (CT $_have). Use 'pve-compose adopt ${_ctid:-$_have} --force' to overwrite."
    fi

    _dir=$(resolve_strip_slash "$(pwd)")
    _dirname=$(basename "$_dir")

    # ── Find the container ──
    if [ -n "$_ctid" ]; then
        resolve_conf_exists "$_ctid" || die "Container $_ctid does not exist"
        info "Using CT $_ctid"
    else
        _rc=0
        _ctid=$(resolve_ct_by_path "$_dir") || _rc=$?
        [ "$_rc" = "2" ] && die "Several containers mount $_dir (CT $_ctid). Pick one: pve-compose adopt <ctid>"
        if [ -n "$_ctid" ] && [ "$_rc" = "0" ]; then
            info "Detected CT $_ctid (bind mount of $_dir)"
        else
            _rc=0
            _ctid=$(resolve_ct_by_hostname "$_dirname") || _rc=$?
            [ "$_rc" = "2" ] && die "Several containers are named '$_dirname' (CT $_ctid). Pick one: pve-compose adopt <ctid>"
            if [ -z "$_ctid" ] || [ "$_rc" != "0" ]; then
                die "No container found for $_dir. Pass the CTID: pve-compose adopt <ctid>"
            fi
            info "Detected CT $_ctid (hostname '$_dirname')"
        fi
    fi

    resolve_is_template "$_ctid" && die "CT $_ctid is a template, not a service container"

    # ── Read the real config ──
    _hostname=$(resolve_conf_field "$_ctid" hostname)
    _cores=$(resolve_conf_field "$_ctid" cores)
    _memory=$(resolve_conf_field "$_ctid" memory)
    _swap=$(resolve_conf_field "$_ctid" swap)
    _dns=$(resolve_conf_field "$_ctid" nameserver)
    _tags_line=$(resolve_conf_field "$_ctid" tags)
    _storage=$(resolve_rootfs_field "$_ctid" storage)
    _disk=$(resolve_rootfs_field "$_ctid" size)
    _ipv4=$(resolve_net0_field "$_ctid" ip)
    _gateway=$(resolve_net0_field "$_ctid" gw)
    _bridge=$(resolve_net0_field "$_ctid" bridge)
    _vlan=$(resolve_net0_field "$_ctid" tag)
    _privileged=$(resolve_privileged "$_ctid")
    _features=$(resolve_features "$_ctid")

    # Proxmox leaves memory/swap out of the conf when they are at the default
    [ -n "$_memory" ] || _memory=512
    [ -n "$_swap" ] || _swap=512

    # The template a container came from is not stored anywhere after
    # creation. Use the global template so a rebuild behaves like `up`.
    _template=""
    if config_load_global; then
        # shellcheck disable=SC2154
        _template=$(printf '%s' "$_global_json" | jq -r '.template.ctid // empty' 2>/dev/null)
    fi

    # ── Bind mount: the one that points here, else mp0 ──
    _slot=$(resolve_mp_slot_for "$_ctid" "$_dir") || _slot=""
    if [ -z "$_slot" ] && [ -n "$(resolve_mp_field "$_ctid" 0 source)" ]; then
        _slot=0
    fi
    if [ -n "$_slot" ]; then
        _mnt_src=$(resolve_mp_field "$_ctid" "$_slot" source)
        _mnt_tgt=$(resolve_mp_field "$_ctid" "$_slot" target)
        if [ "$(resolve_strip_slash "$_mnt_src")" != "$_dir" ]; then
            warn "CT $_ctid mounts $_mnt_src, not this directory ($_dir)"
        fi
    else
        _mnt_src="$_dir"
        _mnt_tgt=$(config_get_mount_target)
        warn "CT $_ctid has no bind mount. lxc.json points to $_mnt_src → $_mnt_tgt; 'pve-compose apply' would add it."
    fi
    for _n in $(resolve_mp_slots "$_ctid"); do
        [ "$_n" = "$_slot" ] && continue
        info "mp$_n ($(resolve_mp_field "$_ctid" "$_n" source) → $(resolve_mp_field "$_ctid" "$_n" target)) is kept as is, lxc.json tracks one mount"
    done

    # ── Tags: keep them, but turn the plain IP back into the {ipv4} template ──
    _ip_only="${_ipv4%%/*}"
    _tags_json=$(printf '%s' "$_tags_line" | tr ';' '\n' | jq -R -s --arg ip "$_ip_only" '
        split("\n") | map(gsub("^ +| +$"; "")) | map(select(length > 0))
        | map(if . == $ip then "{ipv4}" else . end)
    ')

    _json=$(jq -n \
        --arg hostname "$_hostname" \
        --arg ctid "$_ctid" \
        --arg template "$_template" \
        --arg storage "$_storage" \
        --arg disk "$_disk" \
        --arg cores "$_cores" \
        --arg memory "$_memory" \
        --arg swap "$_swap" \
        --arg ipv4 "$_ipv4" \
        --arg gateway "$_gateway" \
        --arg dns "$_dns" \
        --arg bridge "$_bridge" \
        --arg vlan "$_vlan" \
        --arg privileged "$_privileged" \
        --argjson features "$_features" \
        --argjson tags "$_tags_json" \
        --arg mnt_src "$_mnt_src" \
        --arg mnt_tgt "$_mnt_tgt" \
        '{
            hostname: $hostname,
            ctid: ($ctid | tonumber),
            template: $template,
            storage: $storage,
            disk: $disk,
            cores: (if $cores == "" then "" else ($cores | tonumber) end),
            memory: ($memory | tonumber),
            swap: ($swap | tonumber),
            ipv4: $ipv4,
            gateway: $gateway,
            dns: $dns,
            bridge: $bridge,
            vlan: (if $vlan == "" then "" else ($vlan | tonumber) end),
            tags: $tags,
            privileged: ($privileged == "true"),
            features: $features,
            mount: {source: $mnt_src, target: $mnt_tgt}
        } | with_entries(select(.value != ""))')

    if [ "$_hostname" != "$_dirname" ]; then
        warn "Hostname '$_hostname' differs from directory name '$_dirname' (kept, lxc.json wins)"
    fi
    if [ "$_privileged" = "false" ]; then
        info "CT $_ctid is unprivileged: files on the host are owned by shifted UIDs (+100000)"
    fi

    if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
        info "[dry-run] would write $PVC_LXC_JSON:"
        printf '%s\n' "$_json"
        return 0
    fi

    printf '%s\n' "$_json" > "$PVC_LXC_JSON"
    msg "Adopted CT $_ctid ($_hostname), generated $PVC_LXC_JSON"
    info "Check it with: pve-compose doctor"
}
