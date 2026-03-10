#!/bin/sh
# commands/stats.sh - docker compose stats

cmd_stats() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "stats" "$@"
}
