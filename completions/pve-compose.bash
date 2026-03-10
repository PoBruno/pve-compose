# bash completion for pve-compose
# Installed to /usr/share/bash-completion/completions/pve-compose

# Extract service names from docker-compose.yml in current directory
_pvc_services() {
    local f
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [ -f "$f" ]; then
            awk '
                /^services:/ { svc=1; next }
                svc && indent==0 && /^[ ]*[a-zA-Z_][a-zA-Z0-9_-]*:/ {
                    match($0, /^[ ]*/); indent=RLENGTH
                    sub(/^[ ]*/, ""); sub(/:.*$/, ""); print; next
                }
                svc && indent>0 && /^[^ ]/ { exit }
                svc && indent>0 {
                    match($0, /^[ ]*/);
                    if (RLENGTH==indent && /^[ ]*[a-zA-Z_][a-zA-Z0-9_-]*:/) {
                        sub(/^[ ]*/, ""); sub(/:.*$/, ""); print
                    }
                }' "$f"
            return
        fi
    done
}

# List available commands from commands/*.sh
_pvc_commands() {
    local libdir f
    if [ -d /usr/lib/pve-compose/commands ]; then
        libdir=/usr/lib/pve-compose/commands
    elif [ -n "${PVC_LIB:-}" ] && [ -d "$PVC_LIB/commands" ]; then
        libdir="$PVC_LIB/commands"
    elif [ -L "$(command -v pve-compose 2>/dev/null)" ]; then
        libdir="$(cd "$(dirname "$(readlink -f "$(command -v pve-compose)")")/.." && pwd)/commands"
    elif [ -x "$(command -v pve-compose 2>/dev/null)" ]; then
        libdir="$(cd "$(dirname "$(command -v pve-compose)")/.." && pwd)/commands"
    else
        return
    fi
    [ -d "$libdir" ] || return
    for f in "$libdir"/*.sh; do
        [ -f "$f" ] && basename "$f" .sh
    done
}

_pve_compose() {
    local cur prev cmd
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Find the subcommand (first non-flag argument after pve-compose)
    cmd=""
    local i
    for (( i=1; i < COMP_CWORD; i++ )); do
        case "${COMP_WORDS[i]}" in
            -*) ;;
            *)  cmd="${COMP_WORDS[i]}"; break ;;
        esac
    done

    # No subcommand yet - complete commands or global flags
    if [ -z "$cmd" ]; then
        case "$cur" in
            -*)
                COMPREPLY=( $(compgen -W "--debug --dry-run --version --help" -- "$cur") )
                ;;
            *)
                COMPREPLY=( $(compgen -W "$(_pvc_commands)" -- "$cur") )
                ;;
        esac
        return
    fi

    # Commands that accept service names
    case "$cmd" in
        exec|run|logs|attach|start|stop|restart|kill|pause|unpause|rm|pull|build|create|up|down|ps|top|port|events|images|config)
            COMPREPLY=( $(compgen -W "$(_pvc_services)" -- "$cur") )
            ;;
        template)
            COMPREPLY=( $(compgen -W "create list remove" -- "$cur") )
            ;;
        help)
            COMPREPLY=( $(compgen -W "$(_pvc_commands)" -- "$cur") )
            ;;
    esac
}

complete -F _pve_compose pve-compose
