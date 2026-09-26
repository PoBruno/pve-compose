#!/bin/sh
# lib/resolve.sh - Read existing container configs from /etc/pve/lxc
# Sourced by commands - never executed directly.
# Depends: lib/output.sh
#
# Shared by adopt (build lxc.json from a real container), plan (hint when a
# container already serves this directory) and apply (net0 parsing).
# PVC_LXC_CONF_DIR can be overridden so tests run against fixture files.

PVC_LXC_CONF_DIR="${PVC_LXC_CONF_DIR:-/etc/pve/lxc}"

# resolve_conf_path CTID - path of the container conf file
resolve_conf_path() {
    printf '%s/%s.conf' "$PVC_LXC_CONF_DIR" "$1"
}

# resolve_conf_exists CTID
resolve_conf_exists() {
    test -f "$(resolve_conf_path "$1")"
}

# _resolve_main CTID - main section of the conf (snapshots start at "[name]")
_resolve_main() {
    _rm_conf=$(resolve_conf_path "$1")
    [ -f "$_rm_conf" ] || return 1
    sed '/^\[/,$d' "$_rm_conf"
}

# resolve_strip_slash PATH - drop trailing slashes ("/" stays "/")
resolve_strip_slash() {
    _ss="$1"
    while [ "${#_ss}" -gt 1 ] && [ "${_ss%/}" != "$_ss" ]; do
        _ss="${_ss%/}"
    done
    printf '%s' "$_ss"
}

# resolve_conf_field CTID KEY - value of a simple "key: value" line
resolve_conf_field() {
    _resolve_main "$1" | sed -n "s/^$2: *//p" | head -1
}

# resolve_kv LINE KEY - value of KEY in a "k=v,k=v" compound line
resolve_kv() {
    printf '%s' "$1" | tr ',' '\n' | sed -n "s/^$2=//p" | head -1
}

# resolve_net0_field CTID KEY - ip, gw, bridge, tag, hwaddr, ... from net0
resolve_net0_field() {
    resolve_kv "$(resolve_conf_field "$1" net0)" "$2"
}

# resolve_rootfs_field CTID storage|size
resolve_rootfs_field() {
    _rf_line=$(resolve_conf_field "$1" rootfs)
    case "$2" in
        storage) printf '%s' "${_rf_line%%:*}" ;;
        size)    resolve_kv "$_rf_line" size ;;
    esac
}

# resolve_mp_field CTID N source|target - bind mount N (mpN)
# The source is everything before the first comma, kept exactly as written
# (trailing slash included) so apply can match the existing mpN line.
resolve_mp_field() {
    _mf_line=$(resolve_conf_field "$1" "mp$2")
    [ -n "$_mf_line" ] || return 0
    case "$3" in
        source) printf '%s' "${_mf_line%%,*}" ;;
        target) resolve_kv "$_mf_line" mp ;;
    esac
}

# resolve_mp_slots CTID - list the N of every mpN line, one per line
resolve_mp_slots() {
    _resolve_main "$1" | sed -n 's/^mp\([0-9][0-9]*\):.*/\1/p'
}

# resolve_privileged CTID - "false" when unprivileged: 1, else "true"
resolve_privileged() {
    if [ "$(resolve_conf_field "$1" unprivileged)" = "1" ]; then
        printf 'false'
    else
        printf 'true'
    fi
}

# resolve_features CTID - features line as a JSON object
# nesting and keyctl are always present (false when unset), like lxc.json.
resolve_features() {
    resolve_conf_field "$1" features | tr ',' '\n' | jq -R -s '
        split("\n")
        | map(select(length > 0) | split("="))
        | map({key: .[0], value: (.[1] == "1")})
        | {nesting: false, keyctl: false} + from_entries
    '
}

# resolve_is_template CTID
resolve_is_template() {
    [ "$(resolve_conf_field "$1" template)" = "1" ]
}

# _resolve_ctids - every CTID with a conf file, templates excluded
_resolve_ctids() {
    for _rc_f in "$PVC_LXC_CONF_DIR"/*.conf; do
        [ -f "$_rc_f" ] || continue
        _rc_id=$(basename "$_rc_f" .conf)
        resolve_is_template "$_rc_id" && continue
        printf '%s\n' "$_rc_id"
    done
}

# resolve_mp_slot_for CTID DIR - N of the mpN whose source is DIR (first match)
resolve_mp_slot_for() {
    _ms_dir=$(resolve_strip_slash "$2")
    for _ms_n in $(resolve_mp_slots "$1"); do
        _ms_src=$(resolve_strip_slash "$(resolve_mp_field "$1" "$_ms_n" source)")
        if [ "$_ms_src" = "$_ms_dir" ]; then
            printf '%s' "$_ms_n"
            return 0
        fi
    done
    return 1
}

# resolve_ct_by_path DIR - CTID whose bind mount source is DIR
# Prints the CTID and returns 0 on a single match, returns 1 on no match.
# On several matches prints them space separated and returns 2.
resolve_ct_by_path() {
    _cp_hits=""
    for _cp_id in $(_resolve_ctids); do
        resolve_mp_slot_for "$_cp_id" "$1" >/dev/null && _cp_hits="$_cp_hits $_cp_id"
    done
    _resolve_pick "$_cp_hits"
}

# resolve_ct_by_hostname NAME - CTID with that hostname (same return codes)
resolve_ct_by_hostname() {
    _ch_hits=""
    for _ch_id in $(_resolve_ctids); do
        [ "$(resolve_conf_field "$_ch_id" hostname)" = "$1" ] && _ch_hits="$_ch_hits $_ch_id"
    done
    _resolve_pick "$_ch_hits"
}

_resolve_pick() {
    # shellcheck disable=SC2086
    set -- $1
    case $# in
        0) return 1 ;;
        1) printf '%s' "$1"; return 0 ;;
        *) printf '%s' "$*"; return 2 ;;
    esac
}

# resolve_guard_existing - stop plan/up from generating a second container
# for a directory that an existing container already mounts.
# Only relevant when there is no lxc.json yet.
resolve_guard_existing() {
    _ge_dir=$(resolve_strip_slash "$(pwd)")
    _ge_rc=0
    _ge_ct=$(resolve_ct_by_path "$_ge_dir") || _ge_rc=$?
    case "$_ge_rc" in
        0) die "CT $_ge_ct ($(resolve_conf_field "$_ge_ct" hostname)) already mounts $_ge_dir. Run 'pve-compose adopt' to manage it instead of creating a new container." ;;
        2) die "Containers $_ge_ct already mount $_ge_dir. Run 'pve-compose adopt <ctid>' to manage one of them." ;;
    esac
    return 0
}
