#!/bin/sh
# commands/start.sh - docker compose start

cmd_start() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "start" "$@"
}
