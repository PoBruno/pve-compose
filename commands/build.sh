#!/bin/sh
# commands/build.sh - docker compose build

cmd_build() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "build" "$@"
}
