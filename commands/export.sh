#!/bin/sh
# commands/export.sh - docker compose export

cmd_export() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "export" "$@"
}
