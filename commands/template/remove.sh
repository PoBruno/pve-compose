#!/bin/sh
# commands/template/remove.sh - Remove a pve-compose template

cmd_template_remove() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"

    config_require_jq

    _force=0
    _target=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f) _force=1; shift ;;
            --help|-h)
                cat <<'EOF'
Usage: pve-compose template remove [OPTIONS] [CTID|name]

Remove the pve-compose template registered in global config.
If no argument given, removes the template from global config.

Options:
  --force, -f   Skip confirmation prompt
EOF
                return 0
                ;;
            *) _target="$1"; shift ;;
        esac
    done

    # Load global config to find template
    config_load_global || true
    if [ -z "$_global_json" ]; then
        die "No global config found. Run: pve-compose setup"
    fi

    _gc_ctid=$(printf '%s' "$_global_json" | jq -r '.template.ctid // empty' 2>/dev/null)
    _gc_name=$(printf '%s' "$_global_json" | jq -r '.template.name // empty' 2>/dev/null)

    if [ -z "$_gc_ctid" ]; then
        die "No template configured in global config. Create one first: pve-compose template create"
    fi

    # If target given, resolve to CTID and verify it matches global config
    _ctid="$_gc_ctid"
    if [ -n "$_target" ]; then
        case "$_target" in
            *[!0-9]*)
                # Name - search by hostname in config files
                _found=""
                for _cfile in /etc/pve/lxc/*.conf; do
                    [ -f "$_cfile" ] || continue
                    _cname=$(sed -n 's/^hostname: *//p' "$_cfile")
                    if [ "$_cname" = "$_target" ]; then
                        _found=$(basename "$_cfile" .conf)
                        break
                    fi
                done
                [ -n "$_found" ] || die "Container not found: $_target"
                _ctid="$_found"
                ;;
            *)
                _ctid="$_target"
                ;;
        esac
        if [ "$_ctid" != "$_gc_ctid" ]; then
            die "Container $_ctid is not the registered template (expected CTID $_gc_ctid)."
        fi
    fi

    # Verify CT exists
    if ! lxc_exists "$_ctid"; then
        warn "Container $_ctid does not exist. Cleaning up global config."
        # Remove template entry from global config
        printf '%s' "$_global_json" | jq 'del(.template)' > "$PVC_GLOBAL_CONFIG"
        msg "Template entry removed from global config."
        return 0
    fi

    _name=""
    _conf="/etc/pve/lxc/${_ctid}.conf"
    if [ -f "$_conf" ]; then
        _name=$(sed -n 's/^hostname: *//p' "$_conf")
    fi
    [ -n "$_name" ] || _name="${_gc_name:-CT $_ctid}"

    # Confirmation
    if [ "$_force" = "0" ]; then
        warn "This will permanently destroy template $_ctid ($_name)."
        confirm "Are you sure?" || { info "Aborted."; return 0; }
    fi

    # Destroy CT
    lxc_destroy "$_ctid"

    # Remove template entry from global config
    printf '%s' "$_global_json" | jq 'del(.template)' > "$PVC_GLOBAL_CONFIG"

    msg "Template $_ctid ($_name) removed."
}
