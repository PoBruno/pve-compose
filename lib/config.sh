#!/bin/sh
# lib/config.sh - JSON config parsing for pve-compose
# Sourced by commands - never executed directly.
# Depends: lib/output.sh (for die, debug)

PVC_GLOBAL_CONFIG="${PVC_GLOBAL_CONFIG:-/etc/pve-compose/pve-compose.json}"
PVC_LXC_JSON="lxc.json"
PVC_STATE_DIR=".pve-compose"
export PVC_STATE_DIR

# ── Globals populated by config_load_* ──
_lxc_json=""
_global_json=""

# config_require_jq - die if jq is not available
config_require_jq() {
    command -v jq >/dev/null 2>&1 || die "jq is required (apt install jq)"
}

# config_load_lxc_json - load lxc.json from current directory
# Sets _lxc_json. Returns 1 if file does not exist (not an error).
config_load_lxc_json() {
    if [ -f "$PVC_LXC_JSON" ]; then
        _lxc_json=$(cat "$PVC_LXC_JSON")
        debug "Loaded $PVC_LXC_JSON"
        return 0
    fi
    _lxc_json=""
    debug "No $PVC_LXC_JSON found"
    return 1
}

# config_load_global - load global config
# Sets _global_json. Returns 1 if file does not exist.
config_load_global() {
    if [ -f "$PVC_GLOBAL_CONFIG" ]; then
        _global_json=$(cat "$PVC_GLOBAL_CONFIG")
        debug "Loaded $PVC_GLOBAL_CONFIG"
        return 0
    fi
    _global_json=""
    debug "No global config at $PVC_GLOBAL_CONFIG"
    return 1
}

# config_get_field FIELD [DEFAULT] - resolve field from lxc.json
# Returns value or default. Empty string if neither.
#
# BUGFIX: uses `has()` instead of `//` because jq's `//` operator treats
# `false` and `0`-ish values as empty. Without this, `"swap": 0` (a valid
# way to disable swap) silently falls back to the default 512.
config_get_field() {
    _field="$1"
    _default="${2:-}"
    _val=""

    # Try lxc.json first (has() preserves false/0)
    if [ -n "$_lxc_json" ]; then
        _val=$(printf '%s' "$_lxc_json" \
            | jq -r --arg f "$_field" 'if has($f) and .[$f] != null then .[$f] else empty end' 2>/dev/null)
    fi
    if [ -n "$_val" ]; then
        printf '%s' "$_val"
        return 0
    fi

    # Fallback: global config .defaults.<field>
    if [ -n "$_global_json" ]; then
        _val=$(printf '%s' "$_global_json" \
            | jq -r --arg f "$_field" 'if (.defaults | has($f)) and (.defaults[$f] != null) then .defaults[$f] else empty end' 2>/dev/null)
        if [ -n "$_val" ] && [ "$_val" != "auto" ]; then
            printf '%s' "$_val"
            return 0
        fi
    fi

    # Fallback: hardcoded default
    printf '%s' "$_default"
}

# ─────────────────────────────────────────────────────────────────────
# Validation / normalization helpers
# ─────────────────────────────────────────────────────────────────────

# config_is_uint VALUE - true if value is a non-negative integer
config_is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# config_require_uint VALUE FIELD - die with a clear message if not an integer
# Replaces the old `jq --argjson` behaviour, which blew up with a raw
# "invalid JSON text passed to --argjson" when the user typed e.g. "2048MB".
config_require_uint() {
    config_is_uint "$1" && return 0
    die "Invalid value for '$2': '$1' (expected a whole number, e.g. 1024)"
}

# config_require_bool VALUE FIELD - accept true/false/yes/no/1/0, print canonical
config_require_bool() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        true|yes|1)  printf 'true';  return 0 ;;
        false|no|0)  printf 'false'; return 0 ;;
    esac
    die "Invalid value for '$2': '$1' (expected true or false)"
}

# config_require_vlan VALUE - 802.1q tag: 1-4094, or 0 to clear a tag
# 0 and 4095 are reserved by the standard; 0 is accepted only as "untagged".
config_require_vlan() {
    config_is_uint "$1" || die "Invalid value for 'vlan': '$1' (expected a VLAN ID from 1 to 4094)"
    [ "$1" -le 4094 ] || die "Invalid value for 'vlan': '$1' (VLAN IDs go from 1 to 4094)"
}

# config_normalize_disk VALUE - normalize a disk size to plain GB (no suffix)
#
# `pct create --rootfs storage:N` interprets N as GIGABYTES. The old code did
# `sed 's/[gG]$//'`, which silently turned "512M" into "512" -> 512 GB.
# Accepts: 8, 8G, 8g, 8192M (=8G). Rejects anything below 1G or malformed.
config_normalize_disk() {
    _d=$(printf '%s' "$1" | tr -d ' ')
    case "$_d" in
        *[gG]) _n=${_d%[gG]}
               config_is_uint "$_n" || die "Invalid disk size: '$1'"
               [ "$_n" -ge 1 ] || die "Disk size must be at least 1G (got '$1')"
               printf '%s' "$_n" ;;
        *[mM]) _n=${_d%[mM]}
               config_is_uint "$_n" || die "Invalid disk size: '$1'"
               # only accept exact multiples of 1024M to avoid silent rounding
               [ "$_n" -ge 1024 ] || die "Disk size must be at least 1G (got '$1'). pct sizes rootfs in GB."
               [ $(( _n % 1024 )) -eq 0 ] || die "Disk size '$1' is not a whole number of GB. Use e.g. $(( _n / 1024 + 1 ))G"
               printf '%s' "$(( _n / 1024 ))" ;;
        *)     config_is_uint "$_d" || die "Invalid disk size: '$1' (use e.g. 8G)"
               [ "$_d" -ge 1 ] || die "Disk size must be at least 1G (got '$1')"
               printf '%s' "$_d" ;;
    esac
}

# config_features_to_string JSON - convert features object to pct string
# Accepts either {"nesting":true,"keyctl":false} or a plain string.
# Always emits keys sorted, so string comparison against the .conf is stable.
config_features_to_string() {
    _fj="$1"
    _type=$(printf '%s' "$_fj" | jq -r 'type' 2>/dev/null)
    if [ "$_type" = "string" ]; then
        # already a string - just normalize ordering
        printf '%s' "$_fj" | jq -r '.' | tr ',' '\n' | grep -v '^$' | sort | paste -sd, -
        return 0
    fi
    printf '%s' "$_fj" | jq -r '
        to_entries
        | map(select(.value == true or .value == 1 or .value == "1"))
        | map(.key + "=1")
        | sort
        | join(",")
    ' 2>/dev/null
}

# config_features_normalize STRING - sort a "nesting=1,keyctl=1" string
# Proxmox may store features in a different order than we generate them;
# comparing raw strings caused apply to report a diff on every single run.
config_features_normalize() {
    printf '%s' "$1" | tr ',' '\n' | grep -v '^$' | sort | paste -sd, -
}

# config_get_ctid - shorthand for ctid field
config_get_ctid() {
    config_get_field "ctid" ""
}

# config_get_mount_target - shorthand for mount.target
config_get_mount_target() {
    _val=""
    if [ -n "$_lxc_json" ]; then
        _val=$(printf '%s' "$_lxc_json" | jq -r '.mount.target // empty' 2>/dev/null)
    fi
    if [ -n "$_val" ]; then
        printf '%s' "$_val"
        return 0
    fi
    if [ -n "$_global_json" ]; then
        _val=$(printf '%s' "$_global_json" | jq -r '.mount.target // empty' 2>/dev/null)
    fi
    if [ -n "$_val" ]; then
        printf '%s' "$_val"
        return 0
    fi
    printf '/data'
}

# config_get_mount_source - shorthand for mount.source
config_get_mount_source() {
    _val=""
    if [ -n "$_lxc_json" ]; then
        _val=$(printf '%s' "$_lxc_json" | jq -r '.mount.source // empty' 2>/dev/null)
    fi
    if [ -n "$_val" ]; then
        printf '%s' "$_val"
        return 0
    fi
    # Default: current directory
    pwd
}

# config_write_lxc_json RESOLVED_JSON - write complete lxc.json from resolved config
# Preserves tag templates ({var}) from global config instead of expanded values.
# Uses _global_json if available for raw tag templates.
config_write_lxc_json() {
    _rj="$1"

    # Reconstruct tag templates (preserve {var} patterns, not expanded values)
    _tags_template="{ipv4}"
    if [ -n "$_global_json" ]; then
        _gt=$(printf '%s' "$_global_json" | jq -r '.defaults.tags // empty' 2>/dev/null)
        [ -n "$_gt" ] && _tags_template="$_gt"
    fi
    # Build tag array from semicolon-separated template string
    _tags_arr="[]"
    _old_ifs="$IFS"
    IFS=";"
    for _t in $_tags_template; do
        [ -n "$_t" ] || continue
        _tags_arr=$(printf '%s' "$_tags_arr" | jq --arg t "$_t" '. + [$t]')
    done
    IFS="$_old_ifs"

    # Write complete lxc.json with all resolved fields but template tags
    printf '%s' "$_rj" | jq --argjson tags "$_tags_arr" \
        '{
            hostname: .hostname,
            ctid: .ctid,
            template: .template,
            storage: .storage,
            disk: .disk,
            cores: .cores,
            memory: .memory,
            swap: .swap,
            ipv4: .ipv4,
            gateway: .gateway,
            dns: .dns,
            bridge: .bridge,
            tags: $tags,
            privileged: .privileged,
            features: .features,
            mount: .mount
        } + (if (.vlan // 0) > 0 then {vlan: .vlan} else {} end)' > "$PVC_LXC_JSON"
}
