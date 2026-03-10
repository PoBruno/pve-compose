#!/bin/sh
# lib/engine.sh - Resolution engine for pve-compose
# Resolves all config fields into a concrete lxc.json (no "auto", no empty values).
# Sourced by commands - never executed directly.
# Depends: lib/output.sh, lib/config.sh, lib/detect.sh, lib/tags.sh

# engine_resolve - resolve all fields and output complete lxc.json JSON
# Uses chain: lxc.json > global config > auto-detect > hardcoded defaults
# Exception: "privileged" resolves from lxc.json > default true (NOT from global)
engine_resolve() {
    config_require_jq

    # Load configs (non-fatal if missing)
    config_load_lxc_json || true
    config_load_global || true

    # ── hostname (always basename of $PWD) ──
    _hostname=$(basename "$(pwd)")
    debug "hostname: $_hostname"

    # ── privileged (lxc.json only > default true) ──
    _privileged="true"
    if [ -n "$_lxc_json" ]; then
        _p=$(printf '%s' "$_lxc_json" | jq -r '.privileged // empty' 2>/dev/null)
        if [ -n "$_p" ]; then
            _privileged="$_p"
        fi
    fi
    debug "privileged: $_privileged"

    # ── features (derived from privileged) ──
    if [ "$_privileged" = "true" ]; then
        _feat_nesting="true"
        _feat_keyctl="false"
    else
        _feat_nesting="true"
        _feat_keyctl="true"
    fi

    # ── ctid ──
    _ctid=$(config_get_field "ctid" "")
    if [ -z "$_ctid" ]; then
        _ctid=$(detect_next_ctid) || die "Cannot determine CTID (pvesh not available?)"
    fi
    debug "ctid: $_ctid"

    # ── storage ──
    _storage=$(config_get_field "storage" "")
    if [ -z "$_storage" ] || [ "$_storage" = "auto" ]; then
        _storage=$(detect_storage) || _storage="local"
    fi
    debug "storage: $_storage"

    # ── template ──
    # Chain: lxc.json .template > global .template.ctid > detect OS template > warn
    _template=$(config_get_field "template" "")
    if [ -z "$_template" ] || [ "$_template" = "auto" ]; then
        # Global config .template.ctid (set by `template create`)
        if [ -n "$_global_json" ]; then
            _template=$(printf '%s' "$_global_json" | jq -r '.template.ctid // empty' 2>/dev/null)
        fi
    fi
    if [ -z "$_template" ] || [ "$_template" = "auto" ]; then
        _template=$(detect_template) || _template=""
    fi
    if [ -z "$_template" ]; then
        warn "No template detected. You may need to download one: pveam download local debian-12-standard_12.7-1_amd64.tar.zst"
        _template="debian-12-standard_12.7-1_amd64.tar.zst"
    fi
    debug "template: $_template"

    # ── Simple fields with defaults via config chain ──
    _disk=$(config_get_field "disk" "8G")
    _cores=$(config_get_field "cores" "1")
    _memory=$(config_get_field "memory" "1024")
    _swap=$(config_get_field "swap" "512")
    _ipv4=$(config_get_field "ipv4" "dhcp")
    _bridge=$(config_get_field "bridge" "")

    # ── gateway ──
    _gateway=$(config_get_field "gateway" "")
    if [ -z "$_gateway" ] || [ "$_gateway" = "auto" ]; then
        _gateway=$(detect_gateway) || _gateway=""
    fi

    # ── dns ──
    _dns=$(config_get_field "dns" "")
    if [ -z "$_dns" ] || [ "$_dns" = "auto" ]; then
        _dns=$(detect_dns) || _dns=""
    fi

    # ── bridge ──
    if [ -z "$_bridge" ] || [ "$_bridge" = "auto" ]; then
        _bridge=$(detect_bridge) || _bridge="vmbr0"
    fi

    # ── mount ──
    _mount_source=$(config_get_mount_source)
    _mount_target=$(config_get_mount_target)

    # ── tags ──
    # Tags can be a string template ("{ipv4}") from global config,
    # or a JSON array (["pve-compose","app"]) from lxc.json.
    # Normalize to semicolon-separated string for tags_expand.
    _tags_raw=""
    if [ -n "$_lxc_json" ]; then
        _tags_type=$(printf '%s' "$_lxc_json" | jq -r '.tags | type // "null"' 2>/dev/null)
        case "$_tags_type" in
            array)  _tags_raw=$(printf '%s' "$_lxc_json" | jq -r '.tags | join(";")' 2>/dev/null) ;;
            string) _tags_raw=$(printf '%s' "$_lxc_json" | jq -r '.tags // empty' 2>/dev/null) ;;
        esac
    fi
    if [ -z "$_tags_raw" ] && [ -n "$_global_json" ]; then
        _tags_raw=$(printf '%s' "$_global_json" | jq -r '.defaults.tags // empty' 2>/dev/null)
    fi
    [ -n "$_tags_raw" ] || _tags_raw="{ipv4}"

    debug "disk=$_disk cores=$_cores memory=$_memory swap=$_swap"
    debug "ipv4=$_ipv4 gateway=$_gateway dns=$_dns bridge=$_bridge"
    debug "mount: $_mount_source → $_mount_target"

    # ── Generate resolved JSON (without tags - need it for tags_expand) ──
    _resolved_json=$(jq -n \
        --arg hostname "$_hostname" \
        --argjson ctid "$_ctid" \
        --arg template "$_template" \
        --arg storage "$_storage" \
        --arg disk "$_disk" \
        --argjson cores "$_cores" \
        --argjson memory "$_memory" \
        --argjson swap "$_swap" \
        --arg ipv4 "$_ipv4" \
        --arg gateway "$_gateway" \
        --arg dns "$_dns" \
        --arg bridge "$_bridge" \
        --argjson privileged "$_privileged" \
        --argjson feat_nesting "$_feat_nesting" \
        --argjson feat_keyctl "$_feat_keyctl" \
        --arg mount_source "$_mount_source" \
        --arg mount_target "$_mount_target" \
        '{
            hostname: $hostname,
            ctid: $ctid,
            template: $template,
            storage: $storage,
            disk: $disk,
            cores: $cores,
            memory: $memory,
            swap: $swap,
            ipv4: $ipv4,
            gateway: $gateway,
            dns: $dns,
            bridge: $bridge,
            privileged: $privileged,
            features: {
                nesting: $feat_nesting,
                keyctl: $feat_keyctl
            },
            mount: {
                source: $mount_source,
                target: $mount_target
            }
        }')

    # ── Expand tag templates {hostname}, {ipv4}, etc. ──
    _tags_expanded=$(tags_expand "$_tags_raw" "$_resolved_json")
    debug "tags: '$_tags_raw' → '$_tags_expanded'"

    # ── Convert semicolon-separated tags to JSON array ──
    _tags_json="[]"
    _old_ifs="$IFS"
    IFS=";"
    for _t in $_tags_expanded; do
        [ -n "$_t" ] || continue
        _tags_json=$(printf '%s' "$_tags_json" | jq --arg t "$_t" '. + [$t]')
    done
    IFS="$_old_ifs"

    # ── Add tags to resolved JSON ──
    printf '%s' "$_resolved_json" | jq --argjson tags "$_tags_json" '. + {tags: $tags}'
}
