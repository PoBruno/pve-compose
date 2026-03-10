#!/bin/sh
# commands/commit.sh - docker compose commit

cmd_commit() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "commit" "$@"
}
