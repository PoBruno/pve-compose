#!/bin/sh
# commands/status.sh - Show LXC container and compose status

cmd_status() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"

    config_require_jq
    config_load_lxc_json || die "No lxc.json found. Run 'pve-compose plan' or 'pve-compose up' first."

    _ctid=$(config_get_ctid)
    [ -n "$_ctid" ] || die "No CTID in lxc.json"

    _hostname=$(config_get_field "hostname" "unknown")

    # ── Container info ──
    # shellcheck disable=SC2059
    printf "${_C_BOLD}Container${_C_RESET}\n"
    printf "  CTID:      %s\n" "$_ctid"
    printf "  Hostname:  %s\n" "$_hostname"

    if ! lxc_exists "$_ctid"; then
        # shellcheck disable=SC2059
        printf "  Status:    ${_C_RED}not created${_C_RESET}\n"
        return 0
    fi

    if lxc_is_running "$_ctid"; then
        _status="running"
    else
        _status="stopped"
    fi
    # shellcheck disable=SC2059
    case "$_status" in
        running) printf "  Status:    ${_C_GREEN}running${_C_RESET}\n" ;;
        stopped) printf "  Status:    ${_C_YELLOW}stopped${_C_RESET}\n" ;;
    esac

    # Show IP if running
    if [ "$_status" = "running" ]; then
        _ip=$(lxc_exec "$_ctid" hostname -I 2>/dev/null | awk '{print $1}') || _ip=""
        if [ -n "$_ip" ]; then
            printf "  IP:        %s\n" "$_ip"
        fi
    fi

    # ── Compose info (only if running) ──
    if [ "$_status" = "running" ]; then
        _mount_target=$(config_get_mount_target)
        # shellcheck disable=SC2059
        printf "\n${_C_BOLD}Compose${_C_RESET}\n"
        lxc_exec "$_ctid" docker compose --project-directory "$_mount_target" ps 2>/dev/null || \
            printf "  (docker compose not available or no services running)\n"
    fi
}
