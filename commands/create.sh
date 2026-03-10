#!/bin/sh
# commands/create.sh - docker compose create

cmd_create() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "create" "$@"
}
