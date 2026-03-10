#!/bin/sh
# commands/ps.sh - docker compose ps

cmd_ps() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "ps" "$@"
}
