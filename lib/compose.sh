#!/bin/sh
# lib/compose.sh - Docker Compose pass-through helper
# Sourced by commands - never executed directly.
# Depends: lib/output.sh, lib/config.sh, lib/lxc.sh, lib/docker.sh

# compose_passthrough CMD [ARGS...] - forward command to docker compose inside LXC
# Resolves CTID from lxc.json, ensures LXC is running, executes docker compose.
compose_passthrough() {
    _compose_cmd="$1"
    shift

    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"
    . "$PVC_LIB/lib/docker.sh"

    config_require_jq
    config_load_lxc_json || die "No lxc.json found. Run 'pve-compose plan' or 'pve-compose up' first."

    _ctid=$(config_get_ctid)
    [ -n "$_ctid" ] || die "No CTID in lxc.json"

    _mount_target=$(config_get_mount_target)

    lxc_ensure_running "$_ctid"

    debug "compose passthrough: docker compose --project-directory $_mount_target $_compose_cmd $*"
    docker_compose_exec "$_ctid" --project-directory "$_mount_target" "$_compose_cmd" "$@"
}
