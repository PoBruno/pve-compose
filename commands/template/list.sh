#!/bin/sh
# commands/template/list.sh - List pve-compose templates

cmd_template_list() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"

    config_require_jq

    step "Listing pve-compose templates..."

    # Read template from global config (source of truth)
    config_load_global || true
    if [ -z "$_global_json" ]; then
        info "No global config found. Run: pve-compose setup"
        return 0
    fi

    _tmpl_ctid=$(printf '%s' "$_global_json" | jq -r '.template.ctid // empty' 2>/dev/null)
    _tmpl_name=$(printf '%s' "$_global_json" | jq -r '.template.name // empty' 2>/dev/null)

    if [ -z "$_tmpl_ctid" ]; then
        info "No pve-compose template configured."
        info "Create one with: pve-compose template create"
        return 0
    fi

    # Verify CT exists
    _conf="/etc/pve/lxc/${_tmpl_ctid}.conf"
    if [ ! -f "$_conf" ]; then
        warn "Template CTID $_tmpl_ctid registered in global config but container does not exist."
        info "Create one with: pve-compose template create"
        return 0
    fi

    # Extract info from config file
    [ -n "$_tmpl_name" ] || _tmpl_name=$(sed -n 's/^hostname: *//p' "$_conf")
    _is_tmpl=$(grep -c '^template: 1' "$_conf" || printf '0')

    # Get status via cgroup (fast, ~0ms vs 1091ms pct status)
    if lxc_is_running "$_tmpl_ctid"; then
        _ct_status="running"
    else
        _ct_status="stopped"
    fi

    if [ "$_is_tmpl" -gt 0 ]; then
        _type="template"
    else
        _type="container"
    fi

    # shellcheck disable=SC2059
    printf "${_C_BOLD}%-8s %-10s %-40s %s${_C_RESET}\n" "CTID" "Status" "Name" "Type"
    printf "%-8s %-10s %-40s %s\n" "$_tmpl_ctid" "$_ct_status" "$_tmpl_name" "$_type"
}
