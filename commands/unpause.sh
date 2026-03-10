#!/bin/sh
# commands/unpause.sh - docker compose unpause

cmd_unpause() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "unpause" "$@"
}
