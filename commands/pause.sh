#!/bin/sh
# commands/pause.sh - docker compose pause

cmd_pause() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "pause" "$@"
}
