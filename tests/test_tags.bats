#!/usr/bin/env bats
# tests/test_tags.sh - Unit tests for lib/tags.sh

load test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    . "$PROJECT_ROOT/lib/tags.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ── tags_expand ──

@test "tags_expand: no placeholders returns string as-is" {
    result=$(tags_expand "pve-compose;docker" '{}')
    [ "$result" = "pve-compose;docker" ]
}

@test "tags_expand: expands {hostname}" {
    json='{"hostname":"web"}'
    result=$(tags_expand "pve-compose;{hostname}" "$json")
    [ "$result" = "pve-compose;web" ]
}

@test "tags_expand: expands {ctid}" {
    json='{"ctid":200}'
    result=$(tags_expand "{ctid}" "$json")
    [ "$result" = "200" ]
}

@test "tags_expand: expands multiple placeholders" {
    json='{"hostname":"app","cores":4,"memory":2048}'
    result=$(tags_expand "{hostname};{cores}c;{memory}m" "$json")
    [ "$result" = "app;4c;2048m" ]
}

@test "tags_expand: strips CIDR from ipv4" {
    json='{"ipv4":"192.168.1.10/24"}'
    result=$(tags_expand "ip-{ipv4}" "$json")
    [ "$result" = "ip-192.168.1.10" ]
}

@test "tags_expand: ipv4 without CIDR works" {
    json='{"ipv4":"10.0.0.5"}'
    result=$(tags_expand "{ipv4}" "$json")
    [ "$result" = "10.0.0.5" ]
}

@test "tags_expand: filters out dhcp tag" {
    json='{"hostname":"web","ipv4":"dhcp"}'
    result=$(tags_expand "pve-compose;{hostname};{ipv4}" "$json")
    [ "$result" = "pve-compose;web" ]
}

@test "tags_expand: filters out unresolved placeholders" {
    json='{"hostname":"web"}'
    result=$(tags_expand "{hostname};{unknown_var}" "$json")
    [ "$result" = "web" ]
}

@test "tags_expand: all fields expand correctly" {
    json='{
        "hostname":"app",
        "ctid":200,
        "cores":2,
        "memory":1024,
        "swap":512,
        "storage":"local-zfs",
        "disk":"8",
        "bridge":"vmbr0",
        "ipv4":"10.0.0.1/24",
        "gateway":"10.0.0.254",
        "dns":"1.1.1.1"
    }'
    result=$(tags_expand "{hostname};{ctid};{cores};{memory};{swap};{storage};{disk};{bridge};{ipv4};{gateway};{dns}" "$json")
    [ "$result" = "app;200;2;1024;512;local-zfs;8;vmbr0;10.0.0.1;10.0.0.254;1.1.1.1" ]
}

@test "tags_expand: empty string returns empty" {
    result=$(tags_expand "" '{}')
    [ "$result" = "" ]
}

@test "tags_expand: mixed static and dynamic tags" {
    json='{"hostname":"nginx","ipv4":"192.168.1.50/24"}'
    result=$(tags_expand "pve-compose;{hostname};web;ip-{ipv4}" "$json")
    [ "$result" = "pve-compose;nginx;web;ip-192.168.1.50" ]
}
