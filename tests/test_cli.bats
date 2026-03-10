#!/usr/bin/env bats
# tests/test_cli.sh - Integration tests for bin/pve-compose entry point

load test_helper

PVC_BIN="$PROJECT_ROOT/bin/pve-compose"

# ── Version ──

@test "pve-compose --version: prints version" {
    run "$PVC_BIN" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"pve-compose"* ]]
    [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

# ── Help ──

@test "pve-compose --help: prints usage" {
    run "$PVC_BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"COMMAND"* ]]
}

@test "pve-compose -h: same as --help" {
    run "$PVC_BIN" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ── No arguments ──

@test "pve-compose: no args shows usage" {
    run "$PVC_BIN"
    [[ "$output" == *"Usage:"* ]]
}

# ── Unknown command ──

@test "pve-compose badcommand: exits with error" {
    run "$PVC_BIN" badcommand
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"badcommand"* ]]
}

# ── Debug flag ──

@test "pve-compose --debug --version: debug mode works" {
    run "$PVC_BIN" --debug --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"pve-compose"* ]]
}

# ── Version command ──

@test "pve-compose version: subcommand prints version" {
    run "$PVC_BIN" version
    [ "$status" -eq 0 ]
    [[ "$output" == *"pve-compose"* ]]
}
