#!/bin/sh
# commands/config.sh - docker compose config

cmd_config() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "config" "$@"
}
