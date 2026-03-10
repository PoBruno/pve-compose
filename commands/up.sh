#!/bin/sh
# commands/up.sh - Full orchestration: resolve → create LXC → docker → compose up
# Two paths: fast (CT exists, <0.5s) and create (CT new, ~1-2min)

cmd_up() {
    . "$PVC_LIB/lib/config.sh"
    . "$PVC_LIB/lib/lxc.sh"
    . "$PVC_LIB/lib/docker.sh"

    config_require_jq

    # ── Try fast path: lxc.json + CT exists → skip engine_resolve ──
    if config_load_lxc_json 2>/dev/null; then
        # Single-pass jq: extract ctid + mount_target in 1 call (~8ms)
        _fast=$(jq -r '[.ctid // "", .mount.target // "/data"] | @tsv' "$PVC_LXC_JSON" 2>/dev/null) || _fast=""
        _ctid=$(printf '%s' "$_fast" | cut -f1)
        _mount_target=$(printf '%s' "$_fast" | cut -f2)

        if [ -n "$_ctid" ] && lxc_exists "$_ctid"; then
            # ── FAST PATH: CT exists, skip all detection/resolution ──
            _was_running=1
            lxc_is_running "$_ctid" || _was_running=0

            # Ensure running (cgroup check ~0ms, pct start only if stopped)
            lxc_ensure_running "$_ctid"

            # If CT was just started, wait for Docker daemon to be ready
            if [ "$_was_running" = "0" ]; then
                docker_wait_ready "$_ctid"
            fi

            # Validate mount source is accessible
            _mount_source=$(jq -r '.mount.source // ""' "$PVC_LXC_JSON" 2>/dev/null)
            [ -z "$_mount_source" ] && _mount_source="$PWD"
            if [ ! -d "$_mount_source" ]; then
                die "Mount source not accessible: $_mount_source"
            fi

            # Compose up directly via lxc-attach (~18ms + docker compose time)
            docker_compose_exec "$_ctid" --project-directory "$_mount_target" up "$@"

            _hostname=$(jq -r '.hostname // "unknown"' "$PVC_LXC_JSON" 2>/dev/null)
            msg "CT $_ctid ($_hostname) running - compose up"
            return 0
        fi
    fi

    # ── CREATE PATH: CT does not exist - full engine_resolve ──
    . "$PVC_LIB/lib/detect.sh"
    . "$PVC_LIB/lib/engine.sh"
    . "$PVC_LIB/lib/tags.sh"
    . "$PVC_LIB/lib/mount.sh"
    . "$PVC_LIB/lib/permissions.sh"

    # Zero-config: auto-generate lxc.json if missing
    if [ ! -f "$PVC_LXC_JSON" ]; then
        # Require docker-compose.yml to exist
        _compose_found=0
        for _cf in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
            [ -f "$_cf" ] && _compose_found=1 && break
        done
        [ "$_compose_found" = "1" ] || die "No lxc.json or docker-compose.yml found in $PWD"
        info "No lxc.json found, generating from defaults..."
    fi

    step "Resolving configuration..."
    _resolved=$(engine_resolve)

    # Extract fields
    _ctid=$(printf '%s' "$_resolved" | jq -r '.ctid')
    _hostname=$(printf '%s' "$_resolved" | jq -r '.hostname')
    _template=$(printf '%s' "$_resolved" | jq -r '.template')
    _storage=$(printf '%s' "$_resolved" | jq -r '.storage')
    _disk=$(printf '%s' "$_resolved" | jq -r '.disk')
    _cores=$(printf '%s' "$_resolved" | jq -r '.cores')
    _memory=$(printf '%s' "$_resolved" | jq -r '.memory')
    _swap=$(printf '%s' "$_resolved" | jq -r '.swap')
    _bridge=$(printf '%s' "$_resolved" | jq -r '.bridge')
    _ipv4=$(printf '%s' "$_resolved" | jq -r '.ipv4')
    _gateway=$(printf '%s' "$_resolved" | jq -r '.gateway')
    _dns=$(printf '%s' "$_resolved" | jq -r '.dns')
    _privileged=$(printf '%s' "$_resolved" | jq -r '.privileged')
    _mount_source=$(printf '%s' "$_resolved" | jq -r '.mount.source')
    _mount_target=$(printf '%s' "$_resolved" | jq -r '.mount.target')
    _tags=$(printf '%s' "$_resolved" | jq -r '.tags | join(";")')

    # Build features string
    _features="nesting=1"
    _feat_keyctl=$(printf '%s' "$_resolved" | jq -r '.features.keyctl')
    if [ "$_feat_keyctl" = "true" ]; then
        _features="nesting=1,keyctl=1"
    fi

    # If lxc.json didn't exist, generate a complete one (preserving tag templates)
    if [ ! -f "$PVC_LXC_JSON" ]; then
        config_write_lxc_json "$_resolved"
        msg "Generated $PVC_LXC_JSON"
    fi

    # ── Permission pre-checks ──
    perm_pre_checks

    # ── Check if CT already exists (edge case: lxc.json had no ctid, engine resolved one) ──
    if lxc_exists "$_ctid"; then
        info "Container $_ctid already exists"
    else
        # ── Create LXC - clone from template CTID or create from tarball ──
        _is_clone=0
        case "$_template" in
            *[!0-9]*) ;;  # Contains non-digit - it's a tarball path
            *)
                # Pure numeric - it's a template CTID for cloning
                if lxc_exists "$_template"; then
                    _is_clone=1
                fi
                ;;
        esac

        if [ "$_is_clone" = "1" ]; then
            # Clone from cached template (fast ~10s)
            lxc_clone "$_template" "$_ctid" "$_storage"

            # Reconfigure cloned CT with our settings
            _net0="name=eth0,bridge=$_bridge"
            if [ "$_ipv4" = "dhcp" ]; then
                _net0="$_net0,ip=dhcp"
            else
                _net0="$_net0,ip=$_ipv4"
                if [ -n "$_gateway" ]; then
                    _net0="$_net0,gw=$_gateway"
                fi
            fi
            step "Configuring cloned container $_ctid..."
            _pct_run set "$_ctid" \
                --hostname "$_hostname" \
                --cores "$_cores" \
                --memory "$_memory" \
                --swap "$_swap" \
                --net0 "$_net0" \
                --tags "$_tags"
            if [ -n "$_dns" ]; then
                _pct_run set "$_ctid" --nameserver "$_dns"
            fi
        else
            # Create from OS template tarball (slow ~3min)
            lxc_create "$_ctid" "$_template" "$_storage" "$_disk" \
                "$_hostname" "$_cores" "$_memory" "$_swap" "$_bridge" \
                "$_ipv4" "$_gateway" "$_dns" "$_privileged" "$_features" "$_tags"
        fi

        # ── Configure mount ──
        mount_configure "$_ctid" "$_mount_source" "$_mount_target"

        msg "Container $_ctid ($_hostname) created"
    fi

    # ── Start if not running ──
    lxc_ensure_running "$_ctid"

    # ── Docker check + install ──
    docker_ensure "$_ctid"

    # ── Wait for Docker daemon readiness ──
    docker_wait_ready "$_ctid"

    # ── Permission post-validation ──
    perm_post_validate "$_ctid" || true

    # ── Compose up ──
    step "Running docker compose up..."
    docker_compose_exec "$_ctid" --project-directory "$_mount_target" up "$@"

    msg "CT $_ctid ($_hostname) running - compose up"
}
