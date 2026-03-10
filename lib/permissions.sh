#!/bin/sh
# lib/permissions.sh - Permission engine (passive module)
# Sourced by commands (plan, up) - never executed directly.
# Depends: lib/output.sh, lib/config.sh, lib/lxc.sh

# perm_pre_checks - validate prerequisites before LXC creation
# Called by: plan, up
# Returns 0 if OK, dies on fatal issues.
perm_pre_checks() {
    _mount_src=$(config_get_mount_source)

    # Check mount source exists
    if [ ! -d "$_mount_src" ]; then
        die "Mount source does not exist: $_mount_src
  Fix: mkdir -p '$_mount_src'"
    fi

    # Check mount source is not a symlink
    if [ -L "$_mount_src" ]; then
        _resolved=$(readlink -f "$_mount_src" 2>/dev/null || printf '%s' "$_mount_src")
        die "Mount source is a symlink: $_mount_src → $_resolved
  Proxmox rejects symlinks in bind mounts.
  Fix: Use the resolved path '$_resolved' directly, or move data there."
    fi

    # Check mount source is an absolute path
    case "$_mount_src" in
        /*) : ;;  # OK - absolute path
        *)
            die "Mount source must be an absolute path: $_mount_src
  Fix: Use an absolute path (e.g., $(cd "$_mount_src" 2>/dev/null && pwd || printf '/full/path/to/%s' "$_mount_src"))"
            ;;
    esac

    debug "perm_pre_checks: mount source OK ($_mount_src)"
}

# perm_post_validate CTID - validate permissions after LXC creation
# Called by: up (after container + mount + docker are ready)
# Returns 0 if OK, warns on issues.
perm_post_validate() {
    _ctid="$1"
    _mount_target=$(config_get_mount_target)

    # Test write access inside LXC mount point
    debug "perm_post_validate: testing write on $_mount_target"
    if ! lxc_exec "$_ctid" sh -c "touch '${_mount_target}/.pvc-write-test' && rm -f '${_mount_target}/.pvc-write-test'" 2>/dev/null; then
        _privileged=$(config_get_field "privileged" "true")
        if [ "$_privileged" = "false" ]; then
            warn "Write test failed on $_mount_target inside container $_ctid

  Cause: Container is unprivileged. UID 0 in LXC maps to UID 100000 on host.
         The mount source may be owned by root:root (0:0) but the LXC needs 100000:100000.

  Fix:
    sudo chown -R 100000:100000 $(config_get_mount_source)

  Alternative:
    Set \"privileged\": true in lxc.json (eliminates UID issues, recommended default)"
        else
            warn "Write test failed on $_mount_target inside container $_ctid
  Check mount point permissions."
        fi
        return 1
    fi

    # Test Docker is working
    debug "perm_post_validate: testing Docker"
    if ! lxc_exec "$_ctid" docker info >/dev/null 2>&1; then
        warn "Docker is not responding inside container $_ctid
  Try: pve-compose shell, then 'systemctl status docker'"
        return 1
    fi

    debug "perm_post_validate: all checks passed"
    return 0
}

# perm_diagnose ERROR_MSG CTID - map error to diagnosis + fix
# Called automatically when operations fail with permission errors.
# Prints formatted diagnostic output to stderr.
perm_diagnose() {
    _err_msg="$1"
    _ctid="${2:-}"
    _privileged=$(config_get_field "privileged" "true")
    _mount_src=$(config_get_mount_source)

    # Match known error patterns
    case "$_err_msg" in
        *EPERM*|*EACCES*|*Permission\ denied*|*permission\ denied*)
            if [ "$_privileged" = "false" ]; then
                # shellcheck disable=SC2059
                printf "${_C_RED}✗ Permission error${_C_RESET}\n\n" >&2
                printf '  Cause: Container is unprivileged (CTID %s). UID 0 in LXC maps to UID 100000 on host.\n' "$_ctid" >&2
                printf '         The path %s may need ownership adjusted.\n\n' "$_mount_src" >&2
                printf '  Fix:\n' >&2
                printf '    sudo chown -R 100000:100000 %s\n\n' "$_mount_src" >&2
                printf '  Alternative:\n' >&2
                printf '    Set "privileged": true in lxc.json\n' >&2
            else
                # shellcheck disable=SC2059
                printf "${_C_RED}✗ Permission error${_C_RESET}\n\n" >&2
                printf '  Check file permissions on %s\n' "$_mount_src" >&2
            fi
            ;;
        *keyctl*)
            # shellcheck disable=SC2059
            printf "${_C_RED}✗ keyctl error${_C_RESET}\n\n" >&2
            printf '  Cause: Feature keyctl=1 is missing (required for unprivileged containers).\n\n' >&2
            printf '  Fix:\n' >&2
            printf '    pct set %s -features nesting=1,keyctl=1\n' "$_ctid" >&2
            ;;
        *overlay2*|*overlay*)
            # shellcheck disable=SC2059
            printf "${_C_RED}✗ overlay2 mount error${_C_RESET}\n\n" >&2
            printf '  Cause: Kernel or LXC feature issue with overlay2 storage driver.\n\n' >&2
            printf '  Fix:\n' >&2
            printf '    Ensure nesting=1 feature is enabled:\n' >&2
            printf '    pct set %s -features nesting=1\n' "$_ctid" >&2
            ;;
        *)
            debug "perm_diagnose: unrecognized error pattern"
            ;;
    esac
}
