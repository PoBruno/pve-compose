#!/usr/bin/env bats
# tests/test_config.sh - Unit tests for lib/config.sh

load test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    . "$PROJECT_ROOT/lib/config.sh"
    # Override global config path to temp
    PVC_GLOBAL_CONFIG="$TEST_TMPDIR/pve-compose.json"
    PVC_LXC_JSON="$TEST_TMPDIR/lxc.json"
    _lxc_json=""
    _global_json=""
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ── config_load_lxc_json ──

@test "config_load_lxc_json: returns 0 when lxc.json exists" {
    printf '{"hostname":"test"}' > "$PVC_LXC_JSON"
    run config_load_lxc_json
    [ "$status" -eq 0 ]
}

@test "config_load_lxc_json: returns 1 when lxc.json missing" {
    run config_load_lxc_json
    [ "$status" -eq 1 ]
}

@test "config_load_lxc_json: populates _lxc_json" {
    printf '{"hostname":"myhost"}' > "$PVC_LXC_JSON"
    config_load_lxc_json
    result=$(printf '%s' "$_lxc_json" | jq -r '.hostname')
    [ "$result" = "myhost" ]
}

# ── config_load_global ──

@test "config_load_global: returns 0 when global config exists" {
    printf '{"defaults":{}}' > "$PVC_GLOBAL_CONFIG"
    run config_load_global
    [ "$status" -eq 0 ]
}

@test "config_load_global: returns 1 when global config missing" {
    run config_load_global
    [ "$status" -eq 1 ]
}

# ── config_get_field ──

@test "config_get_field: reads field from lxc.json" {
    _lxc_json='{"hostname":"web","cores":4}'
    result=$(config_get_field "hostname")
    [ "$result" = "web" ]
}

@test "config_get_field: returns default when field missing" {
    _lxc_json='{"hostname":"web"}'
    result=$(config_get_field "cores" "2")
    [ "$result" = "2" ]
}

@test "config_get_field: lxc.json takes priority over global" {
    _lxc_json='{"cores":4}'
    _global_json='{"defaults":{"cores":2}}'
    result=$(config_get_field "cores" "1")
    [ "$result" = "4" ]
}

@test "config_get_field: falls back to global when lxc.json missing field" {
    _lxc_json='{"hostname":"web"}'
    _global_json='{"defaults":{"cores":8}}'
    result=$(config_get_field "cores" "1")
    [ "$result" = "8" ]
}

@test "config_get_field: returns empty string with no default" {
    _lxc_json='{}'
    _global_json=''
    result=$(config_get_field "nonexistent")
    [ "$result" = "" ]
}

# ── config_get_ctid ──

@test "config_get_ctid: returns ctid from lxc.json" {
    _lxc_json='{"ctid":200}'
    result=$(config_get_ctid)
    [ "$result" = "200" ]
}

@test "config_get_ctid: returns empty when no ctid" {
    _lxc_json='{"hostname":"web"}'
    result=$(config_get_ctid)
    [ "$result" = "" ]
}

# ── config_get_mount_target ──

@test "config_get_mount_target: returns mount target from lxc.json" {
    _lxc_json='{"mount":{"target":"/app"}}'
    result=$(config_get_mount_target)
    [ "$result" = "/app" ]
}

@test "config_get_mount_target: defaults to /data" {
    _lxc_json='{}'
    _global_json=''
    result=$(config_get_mount_target)
    [ "$result" = "/data" ]
}

# ── config_get_mount_source ──

@test "config_get_mount_source: returns mount source from lxc.json" {
    _lxc_json='{"mount":{"source":"/opt/app"}}'
    result=$(config_get_mount_source)
    [ "$result" = "/opt/app" ]
}

@test "config_get_mount_source: defaults to pwd" {
    _lxc_json='{}'
    result=$(config_get_mount_source)
    [ "$result" = "$(pwd)" ]
}
