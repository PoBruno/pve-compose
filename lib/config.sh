#!/bin/sh
# lib/config.sh - JSON config parsing for pve-compose
# Sourced by commands - never executed directly.
# Depends: lib/output.sh (for die, debug)

PVC_GLOBAL_CONFIG="/etc/pve-compose/pve-compose.json"
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
config_get_field() {
    _field="$1"
    _default="${2:-}"
    _val=""

    # Try lxc.json first
    if [ -n "$_lxc_json" ]; then
        _val=$(printf '%s' "$_lxc_json" | jq -r ".$_field // empty" 2>/dev/null)
    fi
    if [ -n "$_val" ]; then
        printf '%s' "$_val"
        return 0
    fi

    # Fallback: global config .defaults.<field>
    if [ -n "$_global_json" ]; then
        _val=$(printf '%s' "$_global_json" | jq -r ".defaults.$_field // empty" 2>/dev/null)
        if [ -n "$_val" ] && [ "$_val" != "auto" ]; then
            printf '%s' "$_val"
            return 0
        fi
    fi

    # Fallback: hardcoded default
    printf '%s' "$_default"
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
        }' > "$PVC_LXC_JSON"
}
