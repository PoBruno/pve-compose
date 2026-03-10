#!/bin/sh
# commands/ls.sh - docker compose ls

cmd_ls() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "ls" "$@"
}
