#!/bin/sh
# commands/down.sh - docker compose down, then shut the LXC down
# One LXC is one stack: with the stack down the container only eats RAM.
# `up` brings it back through the fast path in a few seconds.
# --keep-running skips the shutdown (handy when debugging inside the LXC).

cmd_down() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"
    . "$PVC_LIB/lib/docker.sh"

    config_require_jq
    config_load_lxc_json || die "No lxc.json found. Run 'pve-compose plan' or 'pve-compose up' first."

    _ctid=$(config_get_ctid)
    [ -n "$_ctid" ] || die "No CTID in lxc.json"
    lxc_exists "$_ctid" || die "Container $_ctid does not exist"
    _mount_target=$(config_get_mount_target)

    # Split our flag from the ones that go to docker compose (-v, --rmi, ...)
    _keep=0
    _n=$#
    while [ "$_n" -gt 0 ]; do
        _a="$1"
        shift
        if [ "$_a" = "--keep-running" ]; then
            _keep=1
        else
            set -- "$@" "$_a"
        fi
        _n=$(( _n - 1 ))
    done

    if ! lxc_is_running "$_ctid"; then
        info "Container $_ctid is already stopped"
        return 0
    fi

    docker_compose_exec "$_ctid" --project-directory "$_mount_target" down "$@"

    if [ "$_keep" = "1" ]; then
        msg "Compose down, CT $_ctid left running"
        return 0
    fi

    # Graceful shutdown first, hard stop only if it hangs
    step "Shutting down container $_ctid..."
    _pct_run shutdown "$_ctid" --timeout 60 --forceStop 1
    msg "Compose down, CT $_ctid stopped"
}
