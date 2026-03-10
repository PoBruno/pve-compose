#!/bin/sh
# commands/exec.sh - docker compose exec

cmd_exec() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "exec" "$@"
}
