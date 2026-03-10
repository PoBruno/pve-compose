#!/bin/sh
# commands/attach.sh - docker compose attach

cmd_attach() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "attach" "$@"
}
