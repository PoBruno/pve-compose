#!/usr/bin/env bats
# tests/test_resolve.bats - lib/resolve.sh against fixture conf files

load test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export PVC_LXC_CONF_DIR="$PROJECT_ROOT/tests/fixtures/lxc"
    . "$PROJECT_ROOT/lib/resolve.sh"
}

# ── Simple and compound fields ──

@test "resolve_conf_field: reads a simple field" {
    [ "$(resolve_conf_field 117 hostname)" = "strike" ]
    [ "$(resolve_conf_field 117 memory)" = "6144" ]
}

@test "resolve_conf_field: ignores snapshot sections" {
    [ "$(resolve_conf_field 201 hostname)" = "owncloud" ]
}

@test "resolve_net0_field: ip, gw, bridge, tag" {
    [ "$(resolve_net0_field 201 ip)" = "192.168.1.201/24" ]
    [ "$(resolve_net0_field 201 gw)" = "192.168.1.1" ]
    [ "$(resolve_net0_field 201 bridge)" = "vmbr0" ]
    [ "$(resolve_net0_field 201 tag)" = "20" ]
    [ -z "$(resolve_net0_field 117 tag)" ]
}

@test "resolve_rootfs_field: storage and size" {
    [ "$(resolve_rootfs_field 117 storage)" = "ssd" ]
    [ "$(resolve_rootfs_field 117 size)" = "110G" ]
}

@test "resolve_mp_field: keeps the source exactly as written" {
    [ "$(resolve_mp_field 117 0 source)" = "/data/app/navidrome/" ]
    [ "$(resolve_mp_field 117 0 target)" = "/mnt/navidrome" ]
}

@test "resolve_privileged: unprivileged 1 means false, missing means true" {
    [ "$(resolve_privileged 117)" = "false" ]
    [ "$(resolve_privileged 218)" = "true" ]
}

@test "resolve_features: all flags as booleans, nesting/keyctl always present" {
    run resolve_features 201
    [ "$(printf '%s' "$output" | jq -c .)" = '{"nesting":true,"keyctl":true,"fuse":true}' ]
    run resolve_features 218
    [ "$(printf '%s' "$output" | jq -c .)" = '{"nesting":true,"keyctl":false}' ]
}

@test "resolve_strip_slash: trailing slashes, root untouched" {
    [ "$(resolve_strip_slash /data/app/x//)" = "/data/app/x" ]
    [ "$(resolve_strip_slash /)" = "/" ]
}

# ── Container lookup ──

@test "resolve_ct_by_path: matches despite a trailing slash in the conf" {
    run resolve_ct_by_path /data/app/navidrome
    [ "$status" -eq 0 ]
    [ "$output" = "117" ]
}

@test "resolve_ct_by_path: hostname differs from directory" {
    run resolve_ct_by_path /data/app/nextcloud
    [ "$status" -eq 0 ]
    [ "$output" = "201" ]
}

@test "resolve_ct_by_path: finds a mount that is not mp0" {
    run resolve_ct_by_path /data/app/minio
    [ "$output" = "201" ]
    [ "$(resolve_mp_slot_for 201 /data/app/minio)" = "1" ]
}

@test "resolve_ct_by_path: templates are skipped" {
    run resolve_ct_by_path /data/app/vikunja
    [ "$output" = "218" ]
}

@test "resolve_ct_by_path: no match returns 1" {
    run resolve_ct_by_path /data/app/nothing
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "resolve_ct_by_path: several matches return 2 with all CTIDs" {
    run resolve_ct_by_path /data/app/shared
    [ "$status" -eq 2 ]
    [ "$output" = "250 251" ]
}

@test "resolve_ct_by_hostname: finds by hostname" {
    run resolve_ct_by_hostname strike
    [ "$status" -eq 0 ]
    [ "$output" = "117" ]
}
