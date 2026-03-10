#!/bin/sh
# commands/push.sh - docker compose push

cmd_push() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "push" "$@"
}
