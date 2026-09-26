#!/bin/sh
# lib/mount.sh - Bind mount configuration for LXC
# Sourced by commands - never executed directly.
# Depends: lib/output.sh, lib/lxc.sh

# mount_validate SOURCE - validate mount source path
# Dies on: path not found, symlinks, not absolute
mount_validate() {
    _src="$1"

    # Must be absolute path
    case "$_src" in
        /*) ;;
        *)  die "Mount source must be absolute path: $_src" ;;
    esac

    # Must exist
    [ -d "$_src" ] || die "Mount source does not exist: $_src"

    # Must not be a symlink (Proxmox rejects symlinks)
    if [ -L "$_src" ]; then
        _real=$(readlink -f "$_src" 2>/dev/null || true)
        die "Mount source is a symlink: $_src → $_real (Proxmox rejects symlinks in bind mounts)"
    fi
}

# mount_find_slot CTID SOURCE - echo the mpN slot to use for SOURCE
# Reuses the slot already bound to SOURCE; otherwise returns the first free one.
#
# BUGFIX: the old code always wrote to mp0, silently overwriting an existing
# mount point that belonged to something else.
mount_find_slot() {
    _ctid="$1"
    _src="$2"
    _conf="/etc/pve/lxc/${_ctid}.conf"

    [ -f "$_conf" ] || { printf 'mp0'; return 0; }

    # Already mounted from this source? reuse that slot (idempotent)
    # POSIX-safe: grep for a literal prefix, then extract the slot name.
    _existing=$(grep -F ": ${_src}," "$_conf" 2>/dev/null \
        | grep -o '^mp[0-9]*' | head -1)
    if [ -n "$_existing" ]; then
        printf '%s' "$_existing"
        return 0
    fi

    # Otherwise pick the first free slot
    _i=0
    while [ "$_i" -lt 256 ]; do
        if ! grep -q "^mp${_i}:" "$_conf" 2>/dev/null; then
            printf 'mp%s' "$_i"
            return 0
        fi
        _i=$(( _i + 1 ))
    done
    die "No free mount point slot on CT $_ctid (mp0-mp255 all used)"
}

# mount_configure CTID SOURCE TARGET - configure bind mount on LXC
mount_configure() {
    _ctid="$1"
    _src="$2"
    _tgt="$3"

    mount_validate "$_src"

    _slot=$(mount_find_slot "$_ctid" "$_src")

    step "Configuring mount: $_src → $_tgt ($_slot)"
    _pct_run set "$_ctid" "-$_slot" "$_src,mp=$_tgt"
}
