#!/bin/sh
# commands/destroy.sh - Compose down + stop and destroy LXC container

cmd_destroy() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"

    config_require_jq
    config_load_lxc_json || die "No lxc.json found. Nothing to destroy."

    _ctid=$(config_get_ctid)
    [ -n "$_ctid" ] || die "No CTID in lxc.json"

    _hostname=$(config_get_field "hostname" "CT $_ctid")

    # Check if container exists
    if ! lxc_exists "$_ctid"; then
        warn "Container $_ctid does not exist. Nothing to destroy."
        # Clean state dir if it exists
        if [ -d "$PVC_STATE_DIR" ]; then
            rm -rf "$PVC_STATE_DIR"
            debug "Removed $PVC_STATE_DIR"
        fi
        return 0
    fi

    # ── Confirmation (unless --force) ──
    _force=0
    for _arg in "$@"; do
        case "$_arg" in
            --force|-f) _force=1 ;;
        esac
    done

    if [ "$_force" = "0" ]; then
        warn "This will destroy container $_ctid ($_hostname) and all its data."
        confirm "Are you sure?" || { info "Aborted."; return 0; }
    fi

    # ── 1. Compose down (if running) ──
    if lxc_is_running "$_ctid"; then
        _mount_target=$(config_get_mount_target)
        step "Running compose down..."
        lxc_exec "$_ctid" docker compose --project-directory "$_mount_target" down 2>/dev/null || \
            debug "compose down failed (may not have been running)"
    fi

    # ── 2. Stop container ──
    if lxc_is_running "$_ctid"; then
        lxc_stop "$_ctid"
    fi

    # ── 3. Destroy container ──
    lxc_destroy "$_ctid"

    # ── 4. Clean state directory ──
    if [ -d "$PVC_STATE_DIR" ]; then
        rm -rf "$PVC_STATE_DIR"
        debug "Removed $PVC_STATE_DIR"
    fi

    msg "Container $_ctid ($_hostname) destroyed."
}
