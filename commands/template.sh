#!/bin/sh
# commands/template.sh - Dispatcher for template sub-commands (create/list/remove)

cmd_template() {
    if [ $# -eq 0 ]; then
        cat <<'EOF'
Usage: pve-compose template COMMAND [OPTIONS]

Manage pre-built LXC templates with Docker installed.

Commands:
  create    Create a new template (LXC + Docker pre-installed)
  list      List existing pve-compose templates
  remove    Remove a template

Run 'pve-compose template COMMAND --help' for details.
EOF
        return 0
    fi

    _subcmd="$1"
    shift

    # Validate sub-command name
    case "$_subcmd" in
        *[!a-z0-9-]*)
            die "Invalid template sub-command: $_subcmd"
            ;;
    esac

    _subcmd_file="$PVC_LIB/commands/template/${_subcmd}.sh"

    if [ ! -f "$_subcmd_file" ]; then
        die "Unknown template command: $_subcmd (use: create, list, remove)"
    fi

    # shellcheck source=/dev/null
    . "$_subcmd_file"

    _func_name=$(printf '%s' "$_subcmd" | tr '-' '_')
    "cmd_template_${_func_name}" "$@"
}
