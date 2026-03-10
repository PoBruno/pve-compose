#!/bin/sh
# commands/template/create.sh - Create a pre-built LXC template with Docker installed

cmd_template_create() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/detect.sh"
    . "$PVC_LIB/lib/lxc.sh"
    . "$PVC_LIB/lib/docker.sh"
    . "$PVC_LIB/lib/prompt.sh"

    config_require_jq

    # ── Parse flags ──
    _tmpl_ctid=""
    _tmpl_name=""
    _tmpl_from=""
    _tmpl_unpriv=""
    _tmpl_storage=""
    _tmpl_disk=""
    _tmpl_password=""
    _tmpl_tags=""
    _noninteractive=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --ctid)            _tmpl_ctid="$2"; shift 2 ;;
            --name)            _tmpl_name="$2"; shift 2 ;;
            --from)            _tmpl_from="$2"; shift 2 ;;
            --storage)         _tmpl_storage="$2"; shift 2 ;;
            --disk)            _tmpl_disk="$2"; shift 2 ;;
            --password)        _tmpl_password="$2"; shift 2 ;;
            --tags)            _tmpl_tags="$2"; shift 2 ;;
            --unprivileged)    _tmpl_unpriv="1"; shift ;;
            --non-interactive) _noninteractive=1; shift ;;
            --help|-h)
                cat <<'EOF'
Usage: pve-compose template create [OPTIONS]

Create a pre-built LXC template with Docker installed.
Enables fast cloning (~10s) instead of full creation (~3min).

After creation, updates global config to use this template automatically.

Options:
  --ctid ID           CTID for the template (default: 9000)
  --name NAME         Hostname for the template (default: docker-base)
  --from TEMPLATE     Base OS template (e.g., local:vztmpl/debian-13-...)
  --storage STORAGE   Storage backend for the template
  --disk SIZE         Root disk size (default: 2G)
  --tags TAGS         Proxmox tags, semicolon-separated (default: template)
  --password PASS     Root password (default: copy from Proxmox host)
  --unprivileged      Create unprivileged template
  --non-interactive   Skip interactive wizard, use defaults

Example:
  pve-compose template create                    # interactive wizard
  pve-compose template create --non-interactive  # all defaults
EOF
                return 0
                ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    # ── Load global config for storage default ──
    config_load_global || true

    # ── Resolve defaults ──
    _def_storage=$(config_get_field "storage" "")
    if [ -z "$_def_storage" ] || [ "$_def_storage" = "auto" ]; then
        _def_storage=$(detect_storage 2>/dev/null) || _def_storage="local"
    fi
    _def_from=$(detect_template 2>/dev/null) || _def_from=""
    _def_disk="2G"
    _def_name="docker-base"
    _def_ctid="9000"
    _def_tags="template"
    _def_unpriv="0"
    _def_password="__HOST_HASH__"

    # Apply CLI flags over defaults
    [ -n "$_tmpl_storage" ] || _tmpl_storage="$_def_storage"
    [ -n "$_tmpl_from" ]    || _tmpl_from="$_def_from"
    [ -n "$_tmpl_disk" ]    || _tmpl_disk="$_def_disk"
    [ -n "$_tmpl_name" ]    || _tmpl_name="$_def_name"
    [ -n "$_tmpl_ctid" ]    || _tmpl_ctid="$_def_ctid"
    [ -n "$_tmpl_tags" ]    || _tmpl_tags="$_def_tags"
    [ -n "$_tmpl_unpriv" ]  || _tmpl_unpriv="$_def_unpriv"
    [ -n "$_tmpl_password" ] || _tmpl_password="$_def_password"

    # ── Interactive wizard ──
    if [ "$_noninteractive" = "0" ]; then
        # Pre-cache slow queries before entering wizard
        prompt_loading "Preparing wizard..."
        _cached_storages=$(list_storages_rootdir)
        _cached_templates=$(list_os_templates 2>/dev/null) || _cached_templates=""

        _tc_priv_label="yes"
        [ "$_tmpl_unpriv" = "1" ] && _tc_priv_label="no"
        _tc_pw_label="copy from host"
        [ "$_tmpl_password" != "__HOST_HASH__" ] && _tc_pw_label="custom"
        [ -z "$_tmpl_password" ] && _tc_pw_label="none"

        _summary=$(printf "%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s" \
            "Template defaults:" \
            "  Storage:      $_tmpl_storage" \
            "  OS template:  $_tmpl_from" \
            "  Disk size:    $_tmpl_disk" \
            "  Name:         $_tmpl_name" \
            "  CTID:         $_tmpl_ctid" \
            "  Tags:         $_tmpl_tags" \
            "  Privileged:   $_tc_priv_label" \
            "  Password:     $_tc_pw_label")

        if ! whiptail --title "pve-compose - Template Wizard" \
            --yesno "$_summary\n\nUse these defaults?" 22 76; then

            # 1. Storage
            _storages="$_cached_storages"
            if [ -z "$_storages" ]; then
                die "No storage with rootdir found in /etc/pve/storage.cfg"
            fi
            _storage_count=$(printf '%s\n' "$_storages" | wc -l)
            if [ "$_storage_count" -gt 1 ]; then
                _sel=$(printf '%s\n' "$_storages" | prompt_select_lines "Storage for template")
                _tmpl_storage=$(printf '%s' "$_sel" | awk '{print $1}')
            else
                _tmpl_storage=$(printf '%s' "$_storages" | awk '{print $1}')
            fi

            # 2. OS Template
            _templates="$_cached_templates"
            if [ -z "$_templates" ]; then
                die "No OS templates found. Download one:\n  pveam download local debian-13-standard_13.1-2_amd64.tar.zst"
            fi
            _tmpl_count=$(printf '%s\n' "$_templates" | wc -l)
            if [ "$_tmpl_count" -gt 1 ]; then
                _tmpl_from=$(printf '%s\n' "$_templates" | prompt_select_lines "OS template base")
            else
                _tmpl_from="$_templates"
            fi

            # 3. Disk size
            _tmpl_disk=$(prompt_input "Disk size" "$_tmpl_disk")

            # 4. Name
            _tmpl_name=$(prompt_input "Template name" "$_tmpl_name")

            # 5. CTID
            _tmpl_ctid=$(prompt_input "Template CTID" "$_tmpl_ctid")

            # 6. Tags
            _tmpl_tags=$(prompt_input "Tags (semicolon-separated)" "$_tmpl_tags")

            # 7. Privileged
            if whiptail --title "pve-compose" \
                --yesno "Privileged container?\n\n(Recommended for Docker in LXC)" 10 50; then
                _tmpl_unpriv="0"
            else
                _tmpl_unpriv="1"
            fi

            # 8. Root password
            _host_hash=$(awk -F: '/^root:/{print $2}' /etc/shadow 2>/dev/null) || true
            if [ -n "$_host_hash" ]; then
                _pw_choice=$(prompt_select "Root password" \
                    "Copy from this Proxmox host (recommended)" \
                    "Set a custom password" \
                    "No password (only pct enter, no SSH)")
                case "$_pw_choice" in
                    Copy*)   _tmpl_password="__HOST_HASH__" ;;
                    Set*)    _tmpl_password=$(prompt_password "Enter root password") ;;
                    *)       _tmpl_password="" ;;
                esac
            else
                _pw_choice=$(prompt_select "Root password" \
                    "Set a custom password" \
                    "No password")
                case "$_pw_choice" in
                    Set*)  _tmpl_password=$(prompt_password "Enter root password") ;;
                    *)     _tmpl_password="" ;;
                esac
            fi
        fi
    fi

    # Resolve storage name (strip type suffix)
    _tmpl_storage=$(printf '%s' "$_tmpl_storage" | awk '{print $1}')

    # Strip trailing G for pct
    _disk_num=$(printf '%s' "$_tmpl_disk" | sed 's/[gG]$//')

    # ── Check if CTID already in use ──
    if lxc_exists "$_tmpl_ctid"; then
        die "CTID $_tmpl_ctid already in use. Use --ctid or choose a different ID."
    fi

    # ── Determine features ──
    if [ "$_tmpl_unpriv" = "1" ]; then
        _tmpl_features="nesting=1,keyctl=1"
        _tmpl_priv="false"
    else
        _tmpl_features="nesting=1"
        _tmpl_priv="true"
    fi

    # ── Confirm ──
    if [ "$_noninteractive" = "0" ]; then
        _tc_pw_final="copy from host"
        [ "$_tmpl_password" != "__HOST_HASH__" ] && _tc_pw_final="custom"
        [ -z "$_tmpl_password" ] && _tc_pw_final="none"

        _final=$(printf "%s\n\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s" \
            "Create template with these settings?" \
            "  Name:         $_tmpl_name" \
            "  CTID:         $_tmpl_ctid" \
            "  Storage:      $_tmpl_storage" \
            "  OS:           $_tmpl_from" \
            "  Disk:         $_tmpl_disk" \
            "  Tags:         $_tmpl_tags" \
            "  Privileged:   $_tmpl_priv" \
            "  Password:     $_tc_pw_final")

        whiptail --title "pve-compose - Confirm" \
            --yesno "$_final" 20 76 \
            || { info "Aborted."; return 0; }
    fi

    printf "\n"
    step "Creating template '$_tmpl_name' (CTID $_tmpl_ctid)..."

    # ── 1. Create temporary LXC ──
    lxc_create "$_tmpl_ctid" "$_tmpl_from" "$_tmpl_storage" "$_disk_num" \
        "$_tmpl_name" "1" "512" "256" "vmbr0" \
        "dhcp" "" "" "$_tmpl_priv" "$_tmpl_features" "$_tmpl_tags"

    # ── 2. Start and install Docker ──
    lxc_start "$_tmpl_ctid"

    step "Waiting for network..."
    _retries=0
    while [ "$_retries" -lt 30 ]; do
        if lxc_exec "$_tmpl_ctid" ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
            break
        fi
        sleep 1
        _retries=$(( _retries + 1 ))
    done

    docker_install "$_tmpl_ctid"

    # ── 3. Set root password ──
    if [ "$_tmpl_password" = "__HOST_HASH__" ]; then
        _host_hash=$(awk -F: '/^root:/{print $2}' /etc/shadow)
        step "Setting root password (from Proxmox host)..."
        printf 'root:%s\n' "$_host_hash" | lxc_exec "$_tmpl_ctid" chpasswd -e
    elif [ -n "$_tmpl_password" ]; then
        step "Setting root password..."
        printf 'root:%s\n' "$_tmpl_password" | lxc_exec "$_tmpl_ctid" chpasswd
    fi

    # ── 4. Cleanup ──
    step "Cleaning up for template..."
    lxc_exec "$_tmpl_ctid" sh -c '
        apt-get clean 2>/dev/null || apk cache clean 2>/dev/null || true
        rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/* /tmp/* /var/tmp/*
        rm -f /var/log/*.log /var/log/apt/* 2>/dev/null || true
    '

    # ── 5. Stop and convert to template ──
    lxc_stop "$_tmpl_ctid"

    step "Converting to Proxmox template..."
    _pct_run template "$_tmpl_ctid"

    # ── 6. Update global config with template info ──
    step "Updating global config..."
    _dir=$(dirname "$PVC_GLOBAL_CONFIG")
    mkdir -p "$_dir"

    _tmpl_section=$(jq -n \
        --argjson ctid "$_tmpl_ctid" \
        --arg name "$_tmpl_name" \
        --arg storage "$_tmpl_storage" \
        '{
            ctid: $ctid,
            name: $name,
            storage: $storage
        }')

    if [ -f "$PVC_GLOBAL_CONFIG" ]; then
        # Merge template section into existing config
        _updated=$(jq --argjson tmpl "$_tmpl_section" '.template = $tmpl' "$PVC_GLOBAL_CONFIG")
        printf '%s\n' "$_updated" > "$PVC_GLOBAL_CONFIG"
    else
        # Create minimal config with just template
        _config=$(jq -n --argjson tmpl "$_tmpl_section" '{ template: $tmpl }')
        printf '%s\n' "$_config" > "$PVC_GLOBAL_CONFIG"
    fi

    printf "\n"
    msg "Template '$_tmpl_name' created (CTID $_tmpl_ctid)"
    info "Global config updated: template.ctid=$_tmpl_ctid"
    info "Next 'pve-compose up' will auto-clone this template (~10s)."
}
