#!/bin/sh
# commands/top.sh - docker compose top

cmd_top() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "top" "$@"
}
