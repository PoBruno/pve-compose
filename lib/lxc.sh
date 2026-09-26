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
#
# BUGFIX: the old loop slept 0.1s but incremented the counter by 1, so a
# "timeout" of 100 actually waited 10 seconds. Now counts in tenths.
lxc_wait_running() {
    _wctid="$1"
    _timeout="${2:-10}"
    _ticks=$(( _timeout * 10 ))   # 0.1s per tick
    _elapsed=0
    while [ "$_elapsed" -lt "$_ticks" ]; do
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

# lxc_build_net0 BRIDGE IPV4 GATEWAY [VLAN] - net0 string for a new container
# VLAN 1-4094 adds an 802.1q tag; empty or 0 means untagged.
lxc_build_net0() {
    _bn="name=eth0,bridge=$1"
    if [ "$2" = "dhcp" ]; then
        _bn="$_bn,ip=dhcp"
    else
        _bn="$_bn,ip=$2"
        [ -n "$3" ] && _bn="$_bn,gw=$3"
    fi
    case "${4:-}" in
        ''|0) ;;
        *) _bn="$_bn,tag=$4" ;;
    esac
    printf '%s' "$_bn"
}

# lxc_merge_net0 CURRENT BRIDGE IPV4 GATEWAY VLAN - update an existing net0
# Replaces bridge/ip/gw and keeps everything else (hwaddr, firewall, type,
# mtu...). Rebuilding net0 from scratch gave the container a new MAC address
# and dropped firewall=1 every time the IP changed.
# VLAN: empty keeps the current tag, 0 removes it, 1-4094 sets it.
lxc_merge_net0() {
    _mn_cur="$1" _mn_bridge="$2" _mn_ip="$3" _mn_gw="$4" _mn_vlan="$5"
    _mn_tag=$(printf '%s' "$_mn_cur" | tr ',' '\n' | sed -n 's/^tag=//p')
    case "$_mn_vlan" in
        '') ;;
        0)  _mn_tag="" ;;
        *)  _mn_tag="$_mn_vlan" ;;
    esac
    _mn_keep=$(printf '%s' "$_mn_cur" | tr ',' '\n' \
        | grep -v -e '^name=' -e '^bridge=' -e '^ip=' -e '^gw=' -e '^tag=' -e '^$' \
        | paste -sd, -)
    _mn_new=$(lxc_build_net0 "$_mn_bridge" "$_mn_ip" "$_mn_gw" "$_mn_tag")
    [ -n "$_mn_keep" ] && _mn_new="$_mn_new,$_mn_keep"
    printf '%s' "$_mn_new"
}

# lxc_create - create LXC container from resolved lxc.json fields
# Args: CTID TEMPLATE STORAGE DISK HOSTNAME CORES MEMORY SWAP BRIDGE IPV4 GATEWAY DNS PRIVILEGED FEATURES_STR TAGS [VLAN]
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
    _vlan="${7:-}"

    # Determine unprivileged flag
    if [ "$_privileged" = "true" ]; then
        _unpriv=0
    else
        _unpriv=1
    fi

    _net0=$(lxc_build_net0 "$_bridge" "$_ipv4" "$_gateway" "$_vlan")

    # Resolve template path (add local:vztmpl/ prefix if needed)
    case "$_template" in
        *:*) _tmpl_path="$_template" ;;               # already has storage prefix
        */*) _tmpl_path="$_template" ;;                # full path
        *)   _tmpl_path="local:vztmpl/$_template" ;;   # bare filename
    esac

    # Strip trailing G/g from disk size (pct expects number only).
    # config_normalize_disk already rejects bad units upstream; this is a
    # last-resort guard in case lxc_create is called directly.
    _disk=$(printf '%s' "$_disk" | sed 's/[gG]$//')

    # Re-check the CTID right before creating. detect_next_ctid may have run
    # minutes earlier (slow interactive wizard) and the ID could be taken now.
    if lxc_exists "$_ctid"; then
        die "CTID $_ctid is already in use (container exists). Pick another ctid in lxc.json."
    fi

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

# lxc_grow_rootfs CTID SIZE - grow rootfs to SIZE (e.g. "8G" or "8") if smaller
# A clone inherits the template's rootfs size (often 2G), and `pct clone` has
# no size option, so the requested disk was silently ignored on the clone path.
# Only grows: shrinking a rootfs is not supported by Proxmox.
lxc_grow_rootfs() {
    _ctid="$1"
    _want=$(printf '%s' "$2" | sed 's/[gG]$//')
    _conf="/etc/pve/lxc/${_ctid}.conf"

    [ -f "$_conf" ] || return 0   # dry-run: container was never created
    _cur=$(sed -n '/^\[/q; s/^rootfs: .*size=\([0-9]*\)[gG].*/\1/p' "$_conf")
    [ -n "$_cur" ] || { warn "Could not read rootfs size of CT $_ctid - skipping resize"; return 0; }

    if [ "$_want" -gt "$_cur" ]; then
        step "Growing rootfs of $_ctid: ${_cur}G → ${_want}G..."
        _pct_run resize "$_ctid" rootfs "${_want}G"
    elif [ "$_want" -lt "$_cur" ]; then
        warn "Requested disk ${_want}G is smaller than the template's ${_cur}G - keeping ${_cur}G"
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
