#!/bin/sh
# commands/version.sh - Show pve-compose version

cmd_version() {
    printf 'pve-compose %s\n' "$PVC_VERSION"
}
