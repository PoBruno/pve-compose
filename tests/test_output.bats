#!/usr/bin/env bats
# tests/test_output.sh - Unit tests for lib/output.sh

load test_helper

# ── msg ──

@test "msg: prints green checkmark message" {
    run msg "hello world"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello world"* ]]
}

# ── warn ──

@test "warn: prints warning to stderr" {
    run warn "careful now"
    [ "$status" -eq 0 ]
    [[ "$output" == *"careful now"* ]]
}

# ── info ──

@test "info: prints info message" {
    run info "some info"
    [ "$status" -eq 0 ]
    [[ "$output" == *"some info"* ]]
}

# ── step ──

@test "step: prints step message" {
    run step "doing thing"
    [ "$status" -eq 0 ]
    [[ "$output" == *"doing thing"* ]]
}

# ── debug ──

@test "debug: silent when PVC_DEBUG=0" {
    PVC_DEBUG=0
    run debug "hidden"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "debug: prints when PVC_DEBUG=1" {
    PVC_DEBUG=1
    run debug "visible"
    [ "$status" -eq 0 ]
    [[ "$output" == *"visible"* ]]
}

# ── die ──

@test "die: exits with code 1" {
    run die "fatal error"
    [ "$status" -eq 1 ]
    [[ "$output" == *"fatal error"* ]]
}
