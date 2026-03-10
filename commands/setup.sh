#!/bin/sh
# commands/setup.sh - Create or reconfigure global pve-compose defaults

cmd_setup() {
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
Usage: pve-compose setup [OPTIONS]

Configure global pve-compose defaults.
Auto-detects Proxmox environment and saves to /etc/pve-compose/pve-compose.json.

These defaults apply to all projects unless overridden by lxc.json.

Options:
  --non-interactive   Skip wizard, use auto-detected defaults
  --force             Overwrite existing config

Example:
  pve-compose setup                    # interactive wizard
  pve-compose setup --non-interactive  # auto-detect everything
EOF
                return 0
                ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    # ── Check existing config ──
    _existing=""
    if [ -f "$PVC_GLOBAL_CONFIG" ]; then
        _existing=$(cat "$PVC_GLOBAL_CONFIG")
        if [ "$_force" = "0" ]; then
            if [ "$_noninteractive" = "1" ]; then
                warn "Global config already exists: $PVC_GLOBAL_CONFIG"
                info "Use --force to overwrite"
                return 0
            fi
            if ! whiptail --title "pve-compose - Setup" \
                --yesno "Global config already exists.\nOverwrite?" 10 50; then
                info "Aborted."
                return 0
            fi
        fi
    fi

    # ── Auto-detect defaults ──
    step "Detecting Proxmox environment..."
    _storage=$(detect_storage 2>/dev/null) || _storage="local"
    _gateway=$(detect_gateway 2>/dev/null) || _gateway=""
    _dns=$(detect_dns 2>/dev/null) || _dns=""
    _bridge=$(detect_bridge 2>/dev/null) || _bridge="vmbr0"
    _disk="8G"
    _cores="1"
    _memory="1024"
    _swap="512"
    _ipv4="dhcp"
    _tags="{ipv4}"
    _mount_target="/data"

    # ── Interactive wizard ──
    if [ "$_noninteractive" = "0" ]; then
        # Pre-cache slow queries before entering wizard
        prompt_loading "Preparing wizard..."
        _cached_storages=$(list_storages_rootdir)

        _summary=$(printf "%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s" \
            "Auto-detected environment:" \
            "  Storage:       $_storage" \
            "  Disk:          $_disk" \
            "  Cores:         $_cores" \
            "  Memory:        ${_memory}MB" \
            "  Swap:          ${_swap}MB" \
            "  Bridge:        $_bridge" \
            "  IPv4:          $_ipv4" \
            "  Gateway:       $_gateway" \
            "  DNS:           $_dns" \
            "  Tags:          $_tags" \
            "  LXC mount dir: $_mount_target")

        if ! whiptail --title "pve-compose - Global Defaults" \
            --yesno "$_summary\n\nUse these defaults?" 22 70; then

            # 1. Storage
            _storages="$_cached_storages"
            if [ -n "$_storages" ]; then
                _storage_count=$(printf '%s\n' "$_storages" | wc -l)
                if [ "$_storage_count" -gt 1 ]; then
                    _sel=$(printf '%s\n' "$_storages" | prompt_select_lines "Default storage")
                    _storage=$(printf '%s' "$_sel" | awk '{print $1}')
                else
                    _storage=$(printf '%s' "$_storages" | awk '{print $1}')
                fi
            fi

            # 2-5. Resources
            _disk=$(prompt_input "Default disk size" "$_disk")
            _cores=$(prompt_input "Default CPU cores" "$_cores")
            _memory=$(prompt_input "Default memory (MB)" "$_memory")
            _swap=$(prompt_input "Default swap (MB)" "$_swap")

            # 6-9. Network
            _bridge=$(prompt_input "Network bridge" "$_bridge")
            _ipv4=$(prompt_input "Default IPv4 (dhcp or IP/CIDR)" "$_ipv4")
            _gateway=$(prompt_input "Gateway" "$_gateway")
            _dns=$(prompt_input "DNS server" "$_dns")

            # 10. Tags (support {var} placeholders from lxc.json)
            _tags=$(prompt_input "Tags ({hostname},{ipv4},{cores}... expanded per project)" "$_tags")

            # 11. LXC mount dir
            _mount_target=$(prompt_input "Dir inside LXC where host project is mounted" "$_mount_target")
        fi
    fi

    # ── Preserve template section if it exists ──
    _tmpl_section='{"mode":"auto","name":"auto","storage":"auto"}'
    if [ -n "$_existing" ]; then
        _has_tmpl=$(printf '%s' "$_existing" | jq -r '.template.ctid // empty' 2>/dev/null)
        if [ -n "$_has_tmpl" ]; then
            _tmpl_section=$(printf '%s' "$_existing" | jq '.template')
        fi
    fi

    # ── Build config JSON ──
    _config=$(jq -n \
        --argjson template "$_tmpl_section" \
        --arg storage "$_storage" \
        --arg disk "$_disk" \
        --argjson cores "$_cores" \
        --argjson memory "$_memory" \
        --argjson swap "$_swap" \
        --arg bridge "$_bridge" \
        --arg ipv4 "$_ipv4" \
        --arg gateway "$_gateway" \
        --arg dns "$_dns" \
        --arg tags "$_tags" \
        --arg mount_target "$_mount_target" \
        '{
            template: $template,
            defaults: {
                storage: $storage,
                disk: $disk,
                cores: $cores,
                memory: $memory,
                swap: $swap,
                bridge: $bridge,
                ipv4: $ipv4,
                dns: $dns,
                gateway: $gateway,
                tags: $tags
            },
            mount: {
                target: $mount_target
            }
        }')

    # ── Confirm ──
    if [ "$_noninteractive" = "0" ]; then
        _mt=$(printf '%s' "$_config" | jq -r '.mount.target')
        _preview=$(printf '%s' "$_config" | jq -r '.defaults | "  Storage:       \(.storage)\n  Disk:          \(.disk)\n  Cores:         \(.cores)\n  Memory:        \(.memory)MB\n  Swap:          \(.swap)MB\n  Bridge:        \(.bridge)\n  IPv4:          \(.ipv4)\n  Gateway:       \(.gateway)\n  DNS:           \(.dns)\n  Tags:          \(.tags)"')
        _preview=$(printf '%s\n  LXC mount dir: %s' "$_preview" "$_mt")
        whiptail --title "pve-compose - Save Config" \
            --yesno "Save to $PVC_GLOBAL_CONFIG?\n\n$_preview" 24 70 \
            || { info "Aborted."; return 0; }
    fi

    _dir=$(dirname "$PVC_GLOBAL_CONFIG")
    mkdir -p "$_dir"
    printf '%s\n' "$_config" > "$PVC_GLOBAL_CONFIG"

    msg "Saved $PVC_GLOBAL_CONFIG"
    info "Run 'pve-compose template create' to set up a Docker template."
}
