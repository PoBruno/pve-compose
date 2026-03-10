#!/bin/sh
# commands/events.sh - docker compose events

cmd_events() {
    . "$PVC_LIB/lib/compose.sh"
    compose_passthrough "events" "$@"
}
