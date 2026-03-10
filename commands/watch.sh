#!/bin/sh
# commands/watch.sh - docker compose watch

cmd_watch() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "watch" "$@"
}
