#!/bin/sh
# commands/apply.sh - Apply lxc.json changes to existing container

cmd_apply() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"
    . "$PVC_LIB/lib/tags.sh"

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
    _want_swap=$(printf '%s' "$_lxc_json" | jq -r '.swap // empty')
    _want_ipv4=$(printf '%s' "$_lxc_json" | jq -r '.ipv4 // empty')
    _want_gateway=$(printf '%s' "$_lxc_json" | jq -r '.gateway // empty')
    _want_dns=$(printf '%s' "$_lxc_json" | jq -r '.dns // empty')
    _want_bridge=$(printf '%s' "$_lxc_json" | jq -r '.bridge // empty')

    # Features string
    _want_features="nesting=1"
    _priv=$(printf '%s' "$_lxc_json" | jq -r '.privileged // "true"')
    [ "$_priv" = "false" ] && _want_features="nesting=1,keyctl=1"

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
    _cur_features=$(sed -n 's/^features: *//p' "$_conf")
    _cur_tags=$(sed -n 's/^tags: *//p' "$_conf")

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
    if [ -z "$_hot_args" ] && [ -z "$_restart_args" ]; then
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
