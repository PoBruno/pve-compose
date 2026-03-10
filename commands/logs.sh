#!/bin/sh
# commands/logs.sh - docker compose logs

cmd_logs() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "logs" "$@"
}
