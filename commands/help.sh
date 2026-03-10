#!/bin/sh
# commands/help.sh - Help system with per-command details

# ── Command descriptions ──
_help_description() {
    case "$1" in
        # pve-compose specific
        init)      printf "Create global config with auto-detected defaults" ;;
        plan)      printf "Resolve config and generate lxc.json (dry-run)" ;;
        up)        printf "Create LXC, install Docker, run compose up" ;;
        destroy)   printf "Compose down + stop and destroy LXC container" ;;
        shell)     printf "Open interactive shell in the LXC container" ;;
        status)    printf "Show LXC container and compose status" ;;
        version)   printf "Show pve-compose version" ;;
        help)      printf "Show help for a command" ;;
        template)  printf "Manage LXC templates (create/list/remove)" ;;
        setup)     printf "Configure global pve-compose defaults" ;;
        doctor)    printf "Diagnose project health (10 checks)" ;;
        apply)     printf "Apply lxc.json changes to existing container" ;;
        overview)  printf "List Docker containers across all LXCs" ;;
        # compose pass-through
        attach)    printf "Attach to a service's running container (compose)" ;;
        build)     printf "Build or rebuild services (compose)" ;;
        commit)    printf "Create a new image from a container's changes (compose)" ;;
        config)    printf "Validate and view the Compose file (compose)" ;;
        cp)        printf "Copy files between service containers and host (compose)" ;;
        create)    printf "Create containers for a service (compose)" ;;
        down)      printf "Stop and remove containers, networks (compose)" ;;
        events)    printf "Receive real-time events from containers (compose)" ;;
        exec)      printf "Execute a command in a running service container (compose)" ;;
        export)    printf "Export a service container's filesystem as tar (compose)" ;;
        images)    printf "List images used by created containers (compose)" ;;
        kill)      printf "Force stop service containers (compose)" ;;
        logs)      printf "View output from containers (compose)" ;;
        ls)        printf "List running compose projects (compose)" ;;
        pause)     printf "Pause services (compose)" ;;
        port)      printf "Print public port for a port binding (compose)" ;;
        ps)        printf "List containers (compose)" ;;
        pull)      printf "Pull service images (compose)" ;;
        push)      printf "Push service images (compose)" ;;
        restart)   printf "Restart service containers (compose)" ;;
        rm)        printf "Remove stopped service containers (compose)" ;;
        run)       printf "Run a one-off command on a service (compose)" ;;
        scale)     printf "Scale services (compose)" ;;
        start)     printf "Start services (compose)" ;;
        stats)     printf "Display live resource usage statistics (compose)" ;;
        stop)      printf "Stop services (compose)" ;;
        top)       printf "Display running processes (compose)" ;;
        unpause)   printf "Unpause services (compose)" ;;
        wait)      printf "Block until containers stop (compose)" ;;
        watch)     printf "Watch build context and rebuild on changes (compose)" ;;
        *)         printf "No description available" ;;
    esac
}

cmd_help() {
    if [ $# -eq 0 ]; then
        # No argument: show main usage (same as --help)
        cat <<'EOF'
Usage: pve-compose [OPTIONS] COMMAND [ARGS...]

Docker Compose orchestration for Proxmox LXC

Options:
  --debug       Enable debug output
  --dry-run     Show what would be done without executing
  --version     Show version
  --help        Show this help

pve-compose Commands:
EOF
        for _c in init setup plan up destroy shell status doctor apply overview version template help; do
            printf "  %-14s%s\n" "$_c" "$(_help_description "$_c")"
        done

        printf "\nCompose Commands (pass-through to docker compose):\n"
        for _c in attach build commit config cp create down events exec export \
                  images kill logs ls pause port ps pull push restart rm run \
                  scale start stats stop top unpause wait watch; do
            printf "  %-14s%s\n" "$_c" "$(_help_description "$_c")"
        done

        printf "\nRun 'pve-compose help COMMAND' for more information on a command.\n"
        return 0
    fi

    # With argument: show per-command help
    _target="$1"

    # Validate command name
    case "$_target" in
        *[!a-z0-9-]*) die "Invalid command: $_target" ;;
    esac

    _cmd_file="$PVC_LIB/commands/${_target}.sh"
    if [ ! -f "$_cmd_file" ]; then
        die "Unknown command: $_target"
    fi

    _desc=$(_help_description "$_target")
    # shellcheck disable=SC2059
    printf "${_C_BOLD}pve-compose %s${_C_RESET} - %s\n\n" "$_target" "$_desc"
    printf "Usage: pve-compose [OPTIONS] %s [ARGS...]\n\n" "$_target"

    # Show category-specific tips
    case "$_target" in
        up)
            cat <<'EOF'
Create an LXC container, install Docker, and run compose up.
If the container already exists, just runs compose up.

Flags are passed directly to docker compose up (e.g., -d for detached).

Example:
  pve-compose up -d
EOF
            ;;
        destroy)
            cat <<'EOF'
Stop compose services, stop the LXC container, and destroy it.
Asks for confirmation unless --force is specified.

Does NOT remove lxc.json or docker-compose.yml.

Options:
  --force, -f   Skip confirmation prompt

Example:
  pve-compose destroy
  pve-compose destroy --force
EOF
            ;;
        plan)
            cat <<'EOF'
Resolve configuration and generate lxc.json.
Shows a summary of the resolved configuration without creating anything.

Example:
  pve-compose plan
EOF
            ;;
        init)
            cat <<'EOF'
Create global config at /etc/pve-compose/pve-compose.json with
auto-detected defaults. Requires root. Idempotent.

Example:
  pve-compose init
EOF
            ;;
        shell)
            cat <<'EOF'
Open an interactive shell inside the LXC container via pct enter.
The container must exist and will be started if stopped.

Example:
  pve-compose shell
EOF
            ;;
        status)
            cat <<'EOF'
Show combined LXC container info and docker compose service status.

Example:
  pve-compose status
EOF
            ;;
        template)
            cat <<'EOF'
Manage pre-built LXC templates with Docker installed.

Sub-commands:
  create    Create a new template
  list      List existing pve-compose templates
  remove    Remove a template

Example:
  pve-compose template create
  pve-compose template list
  pve-compose template remove docker-base
EOF
            ;;
        doctor)
            cat <<'EOF'
Run 10 diagnostic checks on the current project:
lxc.json, container existence, running state, Docker, Compose,
mount accessibility, compose config, nesting, disk space.

Exit 0 if all pass, exit 1 if any fail.

Example:
  pve-compose doctor
EOF
            ;;
        apply)
            cat <<'EOF'
Compare lxc.json with the actual container config and apply changes.

Hot-apply fields (no restart): memory, swap, cores, tags, dns
Restart-required fields: hostname, features, network (IP/bridge/gateway)

Example:
  pve-compose apply
EOF
            ;;
        setup)
            cat <<'EOF'
Configure global defaults at /etc/pve-compose/pve-compose.json.
Auto-detects Proxmox environment. Interactive wizard by default.

Options:
  --non-interactive   Use auto-detected defaults
  --force             Overwrite existing config

Example:
  pve-compose setup
  pve-compose setup --non-interactive
EOF
            ;;
        overview)
            cat <<'EOF'
List Docker containers across all running LXCs.
Arguments are passed to docker ps (e.g., -a, --format).

Example:
  pve-compose overview
  pve-compose overview -a
  pve-compose overview --format "table {{.Names}}\t{{.Status}}"
EOF
            ;;
        *)
            # Pass-through commands: suggest forwarding to docker compose help
            printf "This command is forwarded to docker compose inside the LXC container.\n"
            printf "All arguments are passed through to 'docker compose %s'.\n\n" "$_target"
            printf "For docker compose help, run:\n"
            printf "  pve-compose %s --help\n" "$_target"
            ;;
    esac
}
