#!/bin/sh
# commands/cp.sh - docker compose cp

cmd_cp() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "cp" "$@"
}
