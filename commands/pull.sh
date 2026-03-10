#!/bin/sh
# commands/pull.sh - docker compose pull

cmd_pull() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "pull" "$@"
}
