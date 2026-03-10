#!/bin/sh
# commands/wait.sh - docker compose wait

cmd_wait() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "wait" "$@"
}
