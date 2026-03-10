#!/bin/sh
# tests/test_helper.sh - Common setup for bats tests
# Sourced by each test file via load test_helper

# Project root (one level up from tests/)
PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Source libs that tests need
. "$PROJECT_ROOT/lib/output.sh"

# Temp directory for test fixtures
setup() {
    TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}
