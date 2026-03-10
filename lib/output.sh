#!/bin/sh
# lib/output.sh - Output formatting functions for pve-compose
# Sourced by commands - never executed directly.
# shellcheck disable=SC2034

# ── Color setup (only if stdout is a terminal) ──
if [ -t 1 ]; then
    _C_RED='\033[0;31m'
    _C_GREEN='\033[0;32m'
    _C_YELLOW='\033[0;33m'
    _C_BLUE='\033[0;34m'
    _C_CYAN='\033[0;36m'
    _C_BOLD='\033[1m'
    _C_RESET='\033[0m'
else
    _C_RED=''
    _C_GREEN=''
    _C_YELLOW=''
    _C_BLUE=''
    _C_CYAN=''
    _C_BOLD=''
    _C_RESET=''
fi

# die MESSAGE - fatal error, print to stderr and exit 1
die() {
    printf "${_C_RED}✗ %s${_C_RESET}\n" "$*" >&2
    exit 1
}

# msg MESSAGE - success message (green checkmark)
msg() {
    printf "${_C_GREEN}✓${_C_RESET} %s\n" "$*"
}

# warn MESSAGE - warning (yellow)
warn() {
    printf "${_C_YELLOW}⚠ %s${_C_RESET}\n" "$*" >&2
}

# info MESSAGE - informational (blue)
info() {
    printf "${_C_BLUE}ℹ${_C_RESET} %s\n" "$*"
}

# debug MESSAGE - only if PVC_DEBUG is set
debug() {
    [ "${PVC_DEBUG:-0}" = "1" ] || return 0
    printf "${_C_BLUE}[debug]${_C_RESET} %s\n" "$*" >&2
}

# step MESSAGE - progress indicator (bold arrow)
step() {
    printf "${_C_BOLD}▸ %s${_C_RESET}\n" "$*"
}

# confirm PROMPT - interactive [y/N], returns 0 if yes
confirm() {
    printf "%s [y/N] " "$*"
    read -r _answer </dev/tty
    case "$_answer" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}
