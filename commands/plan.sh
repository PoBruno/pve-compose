#!/bin/sh
# commands/plan.sh - Resolve config and generate lxc.json (dry-run)

cmd_plan() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/detect.sh"
    . "$PVC_LIB/lib/engine.sh"
    . "$PVC_LIB/lib/tags.sh"
    . "$PVC_LIB/lib/permissions.sh"

    # Require docker-compose.yml for zero-config
    if [ ! -f "$PVC_LXC_JSON" ]; then
        _compose_found=0
        for _cf in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
            [ -f "$_cf" ] && _compose_found=1 && break
        done
        [ "$_compose_found" = "1" ] || die "No lxc.json or docker-compose.yml found in $PWD"
    fi

    step "Resolving configuration..."

    _resolved=$(engine_resolve)

    # Generate complete lxc.json if it doesn't exist
    if [ ! -f "$PVC_LXC_JSON" ]; then
        config_write_lxc_json "$_resolved"
        msg "Generated $PVC_LXC_JSON"
    fi

    # Permission pre-checks
    perm_pre_checks

    # Print summary
    _hostname=$(printf '%s' "$_resolved" | jq -r '.hostname')
    _ctid=$(printf '%s' "$_resolved" | jq -r '.ctid')
    _storage=$(printf '%s' "$_resolved" | jq -r '.storage')
    _template=$(printf '%s' "$_resolved" | jq -r '.template')
    _disk=$(printf '%s' "$_resolved" | jq -r '.disk')
    _cores=$(printf '%s' "$_resolved" | jq -r '.cores')
    _memory=$(printf '%s' "$_resolved" | jq -r '.memory')
    _ipv4=$(printf '%s' "$_resolved" | jq -r '.ipv4')
    _bridge=$(printf '%s' "$_resolved" | jq -r '.bridge')
    _priv=$(printf '%s' "$_resolved" | jq -r '.privileged')
    _src=$(printf '%s' "$_resolved" | jq -r '.mount.source')
    _tgt=$(printf '%s' "$_resolved" | jq -r '.mount.target')

    printf '\n'
    info "Plan summary:"
    printf '  %-14s %s\n' "Hostname:" "$_hostname"
    printf '  %-14s %s\n' "CTID:" "$_ctid"
    printf '  %-14s %s\n' "Storage:" "$_storage"
    printf '  %-14s %s\n' "Template:" "$_template"
    printf '  %-14s %s\n' "Disk:" "$_disk"
    printf '  %-14s %s cores, %s MB RAM\n' "Resources:" "$_cores" "$_memory"
    printf '  %-14s %s (%s)\n' "Network:" "$_ipv4" "$_bridge"
    printf '  %-14s %s\n' "Privileged:" "$_priv"
    printf '  %-14s %s → %s\n' "Mount:" "$_src" "$_tgt"
}
