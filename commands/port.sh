#!/bin/sh
# commands/port.sh - docker compose port

cmd_port() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "port" "$@"
}
