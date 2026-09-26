#!/usr/bin/env bats
# tests/test_network.bats - net0 helpers and VLAN validation

load test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    . "$PROJECT_ROOT/lib/config.sh"
    . "$PROJECT_ROOT/lib/lxc.sh"
}

# ── lxc_build_net0 ──

@test "lxc_build_net0: static IP with gateway" {
    [ "$(lxc_build_net0 vmbr0 192.168.1.5/24 192.168.1.1)" = "name=eth0,bridge=vmbr0,ip=192.168.1.5/24,gw=192.168.1.1" ]
}

@test "lxc_build_net0: dhcp ignores the gateway" {
    [ "$(lxc_build_net0 vmbr0 dhcp 192.168.1.1)" = "name=eth0,bridge=vmbr0,ip=dhcp" ]
}

@test "lxc_build_net0: VLAN adds tag" {
    [ "$(lxc_build_net0 vmbr0 dhcp "" 20)" = "name=eth0,bridge=vmbr0,ip=dhcp,tag=20" ]
}

@test "lxc_build_net0: VLAN 0 means untagged" {
    [ "$(lxc_build_net0 vmbr0 dhcp "" 0)" = "name=eth0,bridge=vmbr0,ip=dhcp" ]
}

# ── lxc_merge_net0 ──

CUR="name=eth0,bridge=vmbr0,firewall=1,gw=192.168.1.1,hwaddr=BC:24:11:F1:03:1A,ip=192.168.1.15/24,type=veth"

@test "lxc_merge_net0: IP change keeps hwaddr, firewall and type" {
    run lxc_merge_net0 "$CUR" vmbr0 192.168.1.16/24 192.168.1.1 ""
    [ "$output" = "name=eth0,bridge=vmbr0,ip=192.168.1.16/24,gw=192.168.1.1,firewall=1,hwaddr=BC:24:11:F1:03:1A,type=veth" ]
}

@test "lxc_merge_net0: empty VLAN keeps the current tag" {
    run lxc_merge_net0 "name=eth0,bridge=vmbr0,ip=dhcp,tag=30" vmbr0 dhcp "" ""
    [[ "$output" == *"tag=30"* ]]
}

@test "lxc_merge_net0: VLAN 0 removes the tag" {
    run lxc_merge_net0 "name=eth0,bridge=vmbr0,ip=dhcp,tag=30" vmbr0 dhcp "" 0
    [[ "$output" != *"tag="* ]]
}

@test "lxc_merge_net0: VLAN sets or replaces the tag" {
    run lxc_merge_net0 "name=eth0,bridge=vmbr0,ip=dhcp,tag=30" vmbr1 dhcp "" 40
    [ "$output" = "name=eth0,bridge=vmbr1,ip=dhcp,tag=40" ]
}

# ── config_require_vlan ──

@test "config_require_vlan: accepts 1 and 4094" {
    run config_require_vlan 1
    [ "$status" -eq 0 ]
    run config_require_vlan 4094
    [ "$status" -eq 0 ]
}

@test "config_require_vlan: accepts 0 (untagged)" {
    run config_require_vlan 0
    [ "$status" -eq 0 ]
}

@test "config_require_vlan: rejects 4095 and above" {
    run config_require_vlan 4095
    [ "$status" -ne 0 ]
    [[ "$output" == *"1 to 4094"* ]]
}

@test "config_require_vlan: rejects non numbers" {
    run config_require_vlan "vlan20"
    [ "$status" -ne 0 ]
}
