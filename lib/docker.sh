#!/bin/sh
# lib/docker.sh - Docker check + install orchestration
# Sourced by commands - never executed directly.
# Depends: lib/output.sh, lib/lxc.sh

# docker_check CTID - check if Docker is installed in LXC
# Returns 0 if docker exists, 1 otherwise
docker_check() {
    lxc_exec "$1" sh -c "command -v docker" >/dev/null 2>&1
}

# docker_install CTID - install Docker via bootstrap script
docker_install() {
    _ctid="$1"
    _bootstrap="$PVC_LIB/scripts/bootstrap-docker.sh"

    [ -f "$_bootstrap" ] || die "Bootstrap script not found: $_bootstrap"

    step "Installing Docker in container $_ctid..."
    if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
        info "[dry-run] lxc-attach -n $_ctid -- sh < $_bootstrap"
        return 0
    fi
    lxc-attach -n "$_ctid" -- sh < "$_bootstrap"
}

# docker_ensure CTID - check Docker, install if missing
docker_ensure() {
    _ctid="$1"
    if docker_check "$_ctid"; then
        debug "Docker already installed in CT $_ctid"
        return 0
    fi
    docker_install "$_ctid"
    # Verify installation
    if ! docker_check "$_ctid"; then
        die "Docker installation failed in CT $_ctid"
    fi
    msg "Docker installed in CT $_ctid"
}

# docker_wait_ready CTID [TIMEOUT] - wait for Docker daemon to accept connections
# Default timeout: 30s (150 iterations × 0.2s)
docker_wait_ready() {
    _ctid="$1"
    _max="${2:-150}"
    _i=0
    while [ "$_i" -lt "$_max" ]; do
        lxc_exec "$_ctid" sh -c "docker info" >/dev/null 2>&1 && return 0
        sleep 0.2
        _i=$(( _i + 1 ))
    done
    warn "Docker is not responding inside container $_ctid"
    warn "  Try: pve-compose shell, then 'systemctl status docker'"
    return 1
}

# docker_compose_exec CTID ARGS... - run docker compose with correct version
# Detects V2 plugin (docker compose) or V1 standalone (docker-compose)
docker_compose_exec() {
    _ctid="$1"
    shift
    if lxc_exec "$_ctid" sh -c "docker compose version" >/dev/null 2>&1; then
        debug "Using docker compose (V2 plugin)"
        lxc_exec "$_ctid" docker compose "$@"
    elif lxc_exec "$_ctid" sh -c "command -v docker-compose" >/dev/null 2>&1; then
        debug "Using docker-compose (V1 standalone)"
        lxc_exec "$_ctid" docker-compose "$@"
    else
        die "No docker compose found in CT $_ctid"
    fi
}
