#!/bin/sh
# commands/kill.sh - docker compose kill

cmd_kill() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "kill" "$@"
}
