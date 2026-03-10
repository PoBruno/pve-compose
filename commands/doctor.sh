#!/bin/sh
# commands/doctor.sh - Diagnose pve-compose project health (10 checks)

cmd_doctor() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"
    . "$PVC_LIB/lib/docker.sh"

    _pass=0
    _fail=0
    _warn=0
    _skip_ct=0

    # Helper: print check result
    _doc_ok() {
        # shellcheck disable=SC2059
        printf "${_C_GREEN}✓${_C_RESET} %s\n" "$1"
        _pass=$(( _pass + 1 ))
    }
    _doc_fail() {
        # shellcheck disable=SC2059
        printf "${_C_RED}✗${_C_RESET} %s\n" "$1"
        _fail=$(( _fail + 1 ))
    }
    _doc_warn() {
        # shellcheck disable=SC2059
        printf "${_C_YELLOW}⚠${_C_RESET} %s\n" "$1"
        _warn=$(( _warn + 1 ))
    }
    _doc_skip() {
        # shellcheck disable=SC2059
        printf "${_C_YELLOW}⚠${_C_RESET} %s (skipped)\n" "$1"
    }

    # ── 1. lxc.json exists and valid JSON ──
    if [ ! -f "$PVC_LXC_JSON" ]; then
        _doc_fail "lxc.json not found"
        _skip_ct=1
    elif ! jq empty "$PVC_LXC_JSON" 2>/dev/null; then
        _doc_fail "lxc.json is not valid JSON"
        _skip_ct=1
    else
        _doc_ok "lxc.json valid"
    fi

    # ── 2. CTID defined and CT exists ──
    _ctid=""
    if [ "$_skip_ct" = "0" ]; then
        config_load_lxc_json 2>/dev/null || true
        _ctid=$(config_get_ctid 2>/dev/null) || _ctid=""
        if [ -z "$_ctid" ]; then
            _doc_fail "No ctid in lxc.json"
            _skip_ct=1
        elif ! lxc_exists "$_ctid"; then
            _doc_fail "Container $_ctid does not exist"
            _skip_ct=1
        else
            _doc_ok "Container $_ctid exists"
        fi
    else
        _doc_skip "Container exists"
    fi

    # ── 3. CT is running ──
    _running=0
    if [ "$_skip_ct" = "0" ]; then
        if lxc_is_running "$_ctid"; then
            _doc_ok "Container $_ctid is running"
            _running=1
        else
            _doc_warn "Container $_ctid is stopped"
        fi
    else
        _doc_skip "Container running"
    fi

    # ── 4. Docker installed ──
    _docker_ok=0
    if [ "$_running" = "1" ]; then
        _dver=$(lxc_exec "$_ctid" docker --version 2>/dev/null) || _dver=""
        if [ -n "$_dver" ]; then
            _dver_short=$(printf '%s' "$_dver" | sed 's/Docker version \([^,]*\).*/\1/')
            _doc_ok "Docker installed ($_dver_short)"
            _docker_ok=1
        else
            _doc_fail "Docker not installed in CT $_ctid"
        fi
    else
        _doc_skip "Docker installed"
    fi

    # ── 5. Docker Compose available ──
    if [ "$_docker_ok" = "1" ]; then
        _cver=$(lxc_exec "$_ctid" sh -c "docker compose version --short 2>/dev/null || docker-compose version --short 2>/dev/null") || _cver=""
        if [ -n "$_cver" ]; then
            _doc_ok "Docker Compose $_cver"
        else
            _doc_fail "Docker Compose not available in CT $_ctid"
        fi
    else
        _doc_skip "Docker Compose"
    fi

    # ── 6. Bind mount accessible ──
    _mount_target=""
    if [ "$_running" = "1" ]; then
        _mount_target=$(config_get_mount_target 2>/dev/null) || _mount_target="/data"
        if lxc_exec "$_ctid" test -d "$_mount_target" 2>/dev/null; then
            # Write test
            if lxc_exec "$_ctid" sh -c "touch ${_mount_target}/.doctor-test && rm -f ${_mount_target}/.doctor-test" 2>/dev/null; then
                _doc_ok "Mount $_mount_target accessible (read/write)"
            else
                _doc_fail "Mount $_mount_target not writable"
            fi
        else
            _doc_fail "Mount $_mount_target not found in CT $_ctid"
        fi
    else
        _doc_skip "Bind mount"
    fi

    # ── 7. docker-compose.yml in mount point ──
    if [ "$_running" = "1" ] && [ -n "$_mount_target" ]; then
        _compose_found=0
        for _cf in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
            if lxc_exec "$_ctid" test -f "${_mount_target}/${_cf}" 2>/dev/null; then
                _compose_found=1
                break
            fi
        done
        if [ "$_compose_found" = "1" ]; then
            _doc_ok "docker-compose.yml found"
        else
            _doc_fail "No docker-compose.yml in $_mount_target"
        fi
    else
        _doc_skip "docker-compose.yml"
    fi

    # ── 8. Compose config valid ──
    if [ "$_docker_ok" = "1" ] && [ "$_compose_found" = "1" ]; then
        if lxc_exec "$_ctid" sh -c "docker compose --project-directory ${_mount_target} config --quiet" 2>/dev/null; then
            _doc_ok "Compose config valid"
        else
            _doc_fail "Compose config has errors"
        fi
    else
        _doc_skip "Compose config"
    fi

    # ── 9. Nesting enabled ──
    if [ "$_skip_ct" = "0" ]; then
        _conf="/etc/pve/lxc/${_ctid}.conf"
        if grep -q 'nesting=1' "$_conf" 2>/dev/null; then
            _doc_ok "Nesting enabled"
        else
            _doc_fail "Nesting not enabled (required for Docker)"
        fi
    else
        _doc_skip "Nesting"
    fi

    # ── 10. Disk space ──
    if [ "$_running" = "1" ]; then
        _df_out=$(lxc_exec "$_ctid" df -P / 2>/dev/null | tail -1) || _df_out=""
        if [ -n "$_df_out" ]; then
            _pct_used=$(printf '%s' "$_df_out" | awk '{gsub(/%/,"",$5); print $5}')
            _size_total=$(printf '%s' "$_df_out" | awk '{printf "%.1fG", $2/1048576}')
            _size_used=$(printf '%s' "$_df_out" | awk '{printf "%.1fG", $3/1048576}')
            if [ "$_pct_used" -gt 95 ] 2>/dev/null; then
                _doc_fail "Disk usage ${_pct_used}% (${_size_used}/${_size_total}) - critical"
            elif [ "$_pct_used" -gt 90 ] 2>/dev/null; then
                _doc_warn "Disk usage ${_pct_used}% (${_size_used}/${_size_total}) - high"
            else
                _doc_ok "Disk usage ${_pct_used}% (${_size_used}/${_size_total})"
            fi
        else
            _doc_warn "Could not check disk usage"
        fi
    else
        _doc_skip "Disk space"
    fi

    # ── Summary ──
    printf "\n"
    if [ "$_fail" -gt 0 ]; then
        # shellcheck disable=SC2059
        printf "${_C_RED}%d check(s) failed${_C_RESET}" "$_fail"
        [ "$_warn" -gt 0 ] && printf ", %d warning(s)" "$_warn"
        printf "\n"
        return 1
    elif [ "$_warn" -gt 0 ]; then
        # shellcheck disable=SC2059
        printf "${_C_YELLOW}All checks passed with %d warning(s)${_C_RESET}\n" "$_warn"
    else
        # shellcheck disable=SC2059
        printf "${_C_GREEN}All checks passed.${_C_RESET}\n"
    fi
}
