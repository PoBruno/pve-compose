#!/bin/sh
# commands/stop.sh - docker compose stop

cmd_stop() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "stop" "$@"
}
