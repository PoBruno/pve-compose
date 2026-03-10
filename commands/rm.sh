#!/bin/sh
# commands/rm.sh - docker compose rm

cmd_rm() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "rm" "$@"
}
