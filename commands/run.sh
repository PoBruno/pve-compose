#!/bin/sh
# commands/run.sh - docker compose run

cmd_run() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "run" "$@"
}
