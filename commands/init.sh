#!/bin/sh
# commands/init.sh - Create lxc.json for the current project

cmd_init() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/detect.sh"
    . "$PVC_LIB/lib/prompt.sh"

    config_require_jq

    _noninteractive=0
    _force=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --non-interactive) _noninteractive=1; shift ;;
            --force)           _force=1; shift ;;
            --help|-h)
                cat <<'EOF'
Usage: pve-compose init [OPTIONS]

Initialize a pve-compose project in the current directory.
Creates lxc.json with container configuration.

Requires a docker-compose.yml in the current directory.
Without flags, runs an interactive wizard.

Options:
  --non-interactive   Skip wizard, use auto-detected defaults
  --force             Overwrite existing lxc.json

Example:
  pve-compose init                    # interactive wizard
  pve-compose init --non-interactive  # auto-detect everything
EOF
                return 0
                ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    # ── Require docker-compose.yml ──
    _has_compose=0
    for _cf in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        [ -f "$_cf" ] && _has_compose=1 && break
    done
    [ "$_has_compose" = "1" ] || die "No docker-compose.yml found in current directory"

    # ── Check existing lxc.json ──
    if [ -f "$PVC_LXC_JSON" ] && [ "$_force" = "0" ]; then
        warn "lxc.json already exists in this directory"
        if [ "$_noninteractive" = "1" ]; then
            info "Use --force to overwrite"
            return 0
        fi
        if ! whiptail --title "pve-compose - Init" \
            --yesno "lxc.json already exists.\nOverwrite?" 10 50; then
            info "Aborted."
            return 0
        fi
    fi

    # ── Load global config for defaults ──
    config_load_global || true

    # ── Auto-detect defaults ──
    _hostname=$(basename "$(pwd)")
    _ctid=$(detect_next_ctid 2>/dev/null) || _ctid="100"

    # Template: global config .template.ctid first, then OS template
    _template=""
    if [ -n "$_global_json" ]; then
        _template=$(printf '%s' "$_global_json" | jq -r '.template.ctid // empty' 2>/dev/null)
    fi
    if [ -z "$_template" ]; then
        _template=$(detect_template 2>/dev/null) || _template=""
    fi
    _storage=$(config_get_field "storage" "")
    if [ -z "$_storage" ] || [ "$_storage" = "auto" ]; then
        _storage=$(detect_storage 2>/dev/null) || _storage="local"
    fi
    _disk=$(config_get_field "disk" "8G")
    _cores=$(config_get_field "cores" "1")
    _memory=$(config_get_field "memory" "1024")
    _swap=$(config_get_field "swap" "512")
    _ipv4=$(config_get_field "ipv4" "dhcp")
    _gateway=$(config_get_field "gateway" "")
    if [ -z "$_gateway" ] || [ "$_gateway" = "auto" ]; then
        _gateway=$(detect_gateway 2>/dev/null) || true
    fi
    _dns=$(config_get_field "dns" "")
    if [ -z "$_dns" ] || [ "$_dns" = "auto" ]; then
        _dns=$(detect_dns 2>/dev/null) || true
    fi
    _bridge=$(config_get_field "bridge" "")
    if [ -z "$_bridge" ] || [ "$_bridge" = "auto" ]; then
        _bridge=$(detect_bridge 2>/dev/null) || _bridge="vmbr0"
    fi
    _mount_source=$(pwd)
    _mount_target=$(config_get_mount_target)
    _privileged="true"
    _global_tags=$(config_get_field "tags" "pve-compose")
    _tags="${_global_tags};$_hostname"

    # ── Interactive wizard ──
    if [ "$_noninteractive" = "0" ]; then
        # Pre-cache slow queries before entering wizard
        prompt_loading "Preparing wizard..."
        _cached_storages=$(list_storages_rootdir)
        _cached_os_templates=$(list_os_templates 2>/dev/null) || _cached_os_templates=""

        _priv_label="yes"
        [ "$_privileged" = "false" ] && _priv_label="no"

        _summary=$(printf "%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s" \
            "Project: $_hostname" \
            "  CTID:        $_ctid" \
            "  Template:    $_template" \
            "  Storage:     $_storage" \
            "  Disk:        $_disk" \
            "  Cores:       $_cores" \
            "  Memory:      ${_memory}MB" \
            "  Swap:        ${_swap}MB" \
            "  IPv4:        $_ipv4" \
            "  Gateway:     $_gateway" \
            "  DNS:         $_dns" \
            "  Bridge:      $_bridge" \
            "  Tags:        $_tags" \
            "  Privileged:  $_priv_label" \
            "  Bind mount:  host:$_mount_source → LXC:$_mount_target")

        if ! whiptail --title "pve-compose - Init Project" \
            --yesno "$_summary\n\nUse these settings?" 28 76; then

            # 1. Hostname
            _hostname=$(prompt_input "Container hostname" "$_hostname")

            # 2. CTID
            _ctid=$(prompt_input "Container ID (CTID)" "$_ctid")

            # 3. Template (select from available)
            # Show global config template first, then OS templates
            _tmpl_list=""
            if [ -n "$_global_json" ]; then
                _gc_ctid=$(printf '%s' "$_global_json" | jq -r '.template.ctid // empty' 2>/dev/null)
                _gc_name=$(printf '%s' "$_global_json" | jq -r '.template.name // empty' 2>/dev/null)
                if [ -n "$_gc_ctid" ] && [ -f "/etc/pve/lxc/${_gc_ctid}.conf" ]; then
                    [ -n "$_gc_name" ] || _gc_name=$(sed -n 's/^hostname: *//p' "/etc/pve/lxc/${_gc_ctid}.conf")
                    _tmpl_list="${_gc_ctid} (${_gc_name:-template})
"
                fi
            fi
            _os_templates="$_cached_os_templates"
            if [ -n "$_os_templates" ]; then
                _tmpl_list="${_tmpl_list}${_os_templates}
"
            fi
            if [ -n "$_tmpl_list" ]; then
                _tmpl_list=$(printf '%s' "$_tmpl_list" | grep -v '^$')
                _sel=$(printf '%s\n' "$_tmpl_list" | prompt_select_lines "Base template")
                case "$_sel" in
                    [0-9]*)  _template=$(printf '%s' "$_sel" | awk '{print $1}') ;;
                    *)       _template="$_sel" ;;
                esac
            fi

            # 4. Storage
            _storages="$_cached_storages"
            if [ -n "$_storages" ]; then
                _storage_count=$(printf '%s\n' "$_storages" | wc -l)
                if [ "$_storage_count" -gt 1 ]; then
                    _sel=$(printf '%s\n' "$_storages" | prompt_select_lines "Storage for container")
                    _storage=$(printf '%s' "$_sel" | awk '{print $1}')
                else
                    _storage=$(printf '%s' "$_storages" | awk '{print $1}')
                fi
            fi

            # 5-8. Resources
            _disk=$(prompt_input "Disk size" "$_disk")
            _cores=$(prompt_input "CPU cores" "$_cores")
            _memory=$(prompt_input "Memory (MB)" "$_memory")
            _swap=$(prompt_input "Swap (MB)" "$_swap")

            # 9-12. Network
            _ipv4=$(prompt_input "IPv4 (dhcp or IP/CIDR)" "$_ipv4")
            _gateway=$(prompt_input "Gateway" "$_gateway")
            _dns=$(prompt_input "DNS server" "$_dns")
            _bridge=$(prompt_input "Network bridge" "$_bridge")

            # 13. Tags
            _tags=$(prompt_input "Tags (semicolon-separated)" "$_tags")

            # 14. Privileged
            if whiptail --title "pve-compose" \
                --yesno "Privileged container?\n\n(Recommended for Docker in LXC)" 10 50; then
                _privileged="true"
            else
                _privileged="false"
            fi
        fi
    fi

    # ── Derive features ──
    if [ "$_privileged" = "true" ]; then
        _feat_nesting="true"
        _feat_keyctl="false"
    else
        _feat_nesting="true"
        _feat_keyctl="true"
    fi

    # ── Build tags JSON array ──
    _tags_json="[]"
    _old_ifs="$IFS"
    IFS=";"
    for _tag in $_tags; do
        [ -n "$_tag" ] || continue
        _tags_json=$(printf '%s' "$_tags_json" | jq --arg t "$_tag" '. + [$t]')
    done
    IFS="$_old_ifs"

    # ── Build lxc.json ──
    _config=$(jq -n \
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
        --argjson tags "$_tags_json" \
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
            tags: $tags,
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

    # ── Confirm ──
    if [ "$_noninteractive" = "0" ]; then
        _preview=$(printf '%s' "$_config" | jq -r '"  Hostname:    \(.hostname)\n  CTID:        \(.ctid)\n  Template:    \(.template)\n  Storage:     \(.storage)\n  Disk:        \(.disk)\n  Cores:       \(.cores)\n  Memory:      \(.memory)MB\n  IPv4:        \(.ipv4)\n  Gateway:     \(.gateway)\n  DNS:         \(.dns)\n  Bridge:      \(.bridge)\n  Tags:        \(.tags | join(";"\))\n  Privileged:  \(.privileged)\n  Bind mount:  host:\(.mount.source) → LXC:\(.mount.target)"')
        whiptail --title "pve-compose - Confirm" \
            --yesno "Save lxc.json?\n\n$_preview" 26 76 \
            || { info "Aborted."; return 0; }
    fi

    printf '%s\n' "$_config" > "$PVC_LXC_JSON"

    msg "Created $PVC_LXC_JSON"
    info "Run 'pve-compose up' to create and start the container."
}
