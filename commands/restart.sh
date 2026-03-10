#!/bin/sh
# commands/restart.sh - docker compose restart

cmd_restart() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "restart" "$@"
}
