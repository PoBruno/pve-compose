#!/bin/sh
# lib/lxc.sh - LXC operations via pct CLI + fast filesystem/cgroup checks
# Sourced by commands - never executed directly.
# Depends: lib/output.sh

# _pct_run CMD [ARGS...] - run pct command, respecting PVC_DRY_RUN
_pct_run() {
    if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
        info "[dry-run] pct $*"
        return 0
    fi
    debug "pct $*"
    pct "$@"
}

# lxc_exists CTID - check if container exists via pmxcfs (O(1), ~0ms)
lxc_exists() {
    test -f "/etc/pve/lxc/${1}.conf"
}

# lxc_is_running CTID - check if container is running via cgroup + fallback (~0-7ms)
lxc_is_running() {
    # Fast path: cgroupv2 unified (PVE 8.x default)
    test -d "/sys/fs/cgroup/lxc/$1" && return 0
    # Fallback: lxc-info works on any cgroup layout (~3-7ms)
    _state=$(lxc-info -n "$1" -sH 2>/dev/null) || return 1
    [ "$_state" = "RUNNING" ]
}

# lxc_wait_running CTID [TIMEOUT_S] - poll until container is running
# Used after pct start to avoid race condition with lxc-attach
lxc_wait_running() {
    _wctid="$1"
    _timeout="${2:-10}"
    _elapsed=0
    while [ "$_elapsed" -lt "$_timeout" ]; do
        lxc_is_running "$_wctid" && return 0
        sleep 0.1
        _elapsed=$(( _elapsed + 1 ))
    done
    # Final attempt
    lxc_is_running "$_wctid"
}

# lxc_ensure_running CTID - start if not running, wait until ready
lxc_ensure_running() {
    if ! lxc_exists "$1"; then
        die "Container $1 does not exist"
    fi
    if ! lxc_is_running "$1"; then
        step "Starting container $1..."
        _pct_run start "$1"
        if [ "${PVC_DRY_RUN:-0}" != "1" ]; then
            lxc_wait_running "$1" 100 || die "Container $1 failed to start (timeout)"
        fi
    fi
}

# lxc_create - create LXC container from resolved lxc.json fields
# Args: CTID TEMPLATE STORAGE DISK HOSTNAME CORES MEMORY SWAP BRIDGE IPV4 GATEWAY DNS PRIVILEGED FEATURES_STR TAGS
lxc_create() {
    _ctid="$1"
    _template="$2"
    _storage="$3"
    _disk="$4"
    _hostname="$5"
    _cores="$6"
    _memory="$7"
    _swap="$8"
    _bridge="$9"
    shift 9
    _ipv4="$1"
    _gateway="$2"
    _dns="$3"
    _privileged="$4"
    _features="$5"
    _tags="$6"

    # Determine unprivileged flag
    if [ "$_privileged" = "true" ]; then
        _unpriv=0
    else
        _unpriv=1
    fi

    # Build net0 string
    _net0="name=eth0,bridge=$_bridge"
    if [ "$_ipv4" = "dhcp" ]; then
        _net0="$_net0,ip=dhcp"
    else
        _net0="$_net0,ip=$_ipv4"
        if [ -n "$_gateway" ]; then
            _net0="$_net0,gw=$_gateway"
        fi
    fi

    # Resolve template path (add local:vztmpl/ prefix if needed)
    case "$_template" in
        *:*) _tmpl_path="$_template" ;;               # already has storage prefix
        */*) _tmpl_path="$_template" ;;                # full path
        *)   _tmpl_path="local:vztmpl/$_template" ;;   # bare filename
    esac

    # Strip trailing G/g from disk size (pct expects number only)
    _disk=$(printf '%s' "$_disk" | sed 's/[gG]$//')

    step "Creating container $_ctid ($_hostname)..."

    _pct_run create "$_ctid" "$_tmpl_path" \
        --hostname "$_hostname" \
        --cores "$_cores" \
        --memory "$_memory" \
        --swap "$_swap" \
        --rootfs "$_storage:$_disk" \
        --net0 "$_net0" \
        --unprivileged "$_unpriv" \
        --features "$_features" \
        --tags "$_tags"

    # Set DNS if provided
    if [ -n "$_dns" ]; then
        _pct_run set "$_ctid" --nameserver "$_dns"
    fi
}

# lxc_clone SRC_CTID DEST_CTID [STORAGE] - clone template to new container
# If STORAGE matches template's storage → linked clone (fast, CoW on ZFS)
# If STORAGE differs → full clone to target storage
lxc_clone() {
    _src="$1"
    _dst="$2"
    _target_storage="${3:-}"

    # Detect source storage from config
    _src_storage=""
    _conf="/etc/pve/lxc/${_src}.conf"
    if [ -f "$_conf" ]; then
        _src_storage=$(sed -n 's/^rootfs: \([^:]*\):.*/\1/p' "$_conf")
    fi

    step "Cloning template $_src → $_dst..."
    if [ -z "$_target_storage" ] || [ "$_target_storage" = "$_src_storage" ]; then
        # Same storage - linked clone (fast)
        _pct_run clone "$_src" "$_dst"
    else
        # Different storage - full clone
        _pct_run clone "$_src" "$_dst" --full --storage "$_target_storage"
    fi
}

# lxc_start CTID
lxc_start() {
    step "Starting container $1..."
    _pct_run start "$1"
}

# lxc_stop CTID
lxc_stop() {
    step "Stopping container $1..."
    _pct_run stop "$1"
}

# lxc_destroy CTID - force destroy (must be stopped)
lxc_destroy() {
    step "Destroying container $1..."
    _pct_run destroy "$1" --force
}

# lxc_exec CTID CMD [ARGS...] - execute command inside LXC via lxc-attach (55x faster than pct exec)
lxc_exec() {
    _ctid="$1"
    shift
    if [ "${PVC_DRY_RUN:-0}" = "1" ]; then
        info "[dry-run] lxc-attach -n $_ctid -- $*"
        return 0
    fi
    debug "lxc-attach -n $_ctid -- $*"
    lxc-attach -n "$_ctid" -- "$@"
}
