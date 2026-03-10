#!/bin/sh
# lib/detect.sh - Host auto-detection for Proxmox VE
# Sourced by commands - never executed directly.
# Depends: lib/output.sh (for debug, warn)

# detect_storage - detect best storage pool for rootdir
# Priority: zfspool > lvmthin > lvm > dir
# Reads /etc/pve/storage.cfg directly (instant) instead of pvesh API (can hang on CIFS/NFS).
# Returns storage ID or empty string on failure.
detect_storage() {
    _cfg="/etc/pve/storage.cfg"
    if [ ! -f "$_cfg" ]; then
        debug "No storage config at $_cfg"
        return 1
    fi

    # Parse storage.cfg: find storages with "rootdir" in content, grouped by type
    # Format: "type: name\n\tcontent ...\n\t..."
    for _type in zfspool lvmthin lvm dir; do
        _match=$(awk -v t="$_type" '
            /^[a-z]/ { stype=$1; sub(/:$/,"",stype); sname=$2 }
            /content/ && stype == t && /rootdir/ { print sname; exit }
        ' "$_cfg")
        if [ -n "$_match" ]; then
            debug "Detected storage: $_match (type: $_type)"
            printf '%s' "$_match"
            return 0
        fi
    done

    debug "No suitable storage found"
    return 1
}

# detect_gateway - detect default gateway from routing table
detect_gateway() {
    _gw=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
    if [ -n "$_gw" ]; then
        debug "Detected gateway: $_gw"
        printf '%s' "$_gw"
        return 0
    fi
    debug "No default gateway found"
    return 1
}

# detect_dns - detect DNS server
# Tries /etc/resolv.conf (skipping localhost), falls back to gateway
detect_dns() {
    # Skip 127.0.0.1 and ::1 - these won't work inside an LXC
    _dns=$(awk '/^nameserver/ && $2 !~ /^(127\.|::1$)/ {print $2; exit}' /etc/resolv.conf 2>/dev/null)
    if [ -n "$_dns" ]; then
        debug "Detected DNS: $_dns"
        printf '%s' "$_dns"
        return 0
    fi
    # Fallback: use gateway as DNS
    detect_gateway
}

# detect_bridge - detect first available network bridge
detect_bridge() {
    # Try ip link (most reliable)
    _br=$(ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2; exit}')
    if [ -n "$_br" ]; then
        debug "Detected bridge: $_br"
        printf '%s' "$_br"
        return 0
    fi
    # Fallback default
    debug "No bridge detected, defaulting to vmbr0"
    printf 'vmbr0'
}

# detect_template - detect best available LXC template
# Priority: global config .template.ctid > local debian tarball > empty
# Tags are NOT used for template identification (tags are organizational only).
detect_template() {
    # Check global config for cached template CTID
    _gc="/etc/pve-compose/pve-compose.json"
    if [ -f "$_gc" ] && command -v jq >/dev/null 2>&1; then
        _cached=$(jq -r '.template.ctid // empty' "$_gc" 2>/dev/null)
        if [ -n "$_cached" ] && [ -f "/etc/pve/lxc/${_cached}.conf" ]; then
            debug "Detected cached template: CTID $_cached (from global config)"
            printf '%s' "$_cached"
            return 0
        fi
    fi

    # Find latest local Debian template
    _tmpl=$(pveam list local 2>/dev/null | awk '/debian.*standard/ {print $1}' | sort -V | tail -1)
    if [ -n "$_tmpl" ]; then
        debug "Detected template: $_tmpl"
        printf '%s' "$_tmpl"
        return 0
    fi

    debug "No template found"
    return 1
}

# detect_next_ctid - get next available CTID from Proxmox
detect_next_ctid() {
    if ! command -v pvesh >/dev/null 2>&1; then
        debug "pvesh not found, cannot get next CTID"
        return 1
    fi
    _ctid=$(pvesh get /cluster/nextid 2>/dev/null) || {
        debug "pvesh nextid failed"
        return 1
    }
    debug "Next available CTID: $_ctid"
    printf '%s' "$_ctid"
}
