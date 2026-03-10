#!/bin/sh
# commands/down.sh - docker compose down

cmd_down() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "down" "$@"
}
