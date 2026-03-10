#!/bin/sh
# commands/scale.sh - docker compose scale

cmd_scale() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "scale" "$@"
}
