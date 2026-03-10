#!/bin/sh
# commands/images.sh - docker compose images

cmd_images() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "images" "$@"
}
