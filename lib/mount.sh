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

# mount_configure CTID SOURCE TARGET - configure bind mount on LXC
mount_configure() {
    _ctid="$1"
    _src="$2"
    _tgt="$3"

    mount_validate "$_src"

    step "Configuring mount: $_src → $_tgt"
    _pct_run set "$_ctid" -mp0 "$_src,mp=$_tgt"
}
