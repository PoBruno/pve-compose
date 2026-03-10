#!/bin/sh
# commands/shell.sh - Open interactive shell in the LXC container

cmd_shell() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"

    config_require_jq
    config_load_lxc_json || die "No lxc.json found. Run 'pve-compose plan' or 'pve-compose up' first."

    _ctid=$(config_get_ctid)
    [ -n "$_ctid" ] || die "No CTID in lxc.json"

    lxc_ensure_running "$_ctid"

    info "Entering container $_ctid (exit with 'exit' or Ctrl-D)..."
    pct enter "$_ctid"
}
