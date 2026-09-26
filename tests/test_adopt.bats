#!/usr/bin/env bats
# tests/test_adopt.bats - adopt command against fixture conf files (dry-run)

load test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export PVC_LXC_CONF_DIR="$PROJECT_ROOT/tests/fixtures/lxc"
    export PVC_LIB="$PROJECT_ROOT"
    # no global config: the template field is left out
    export PVC_GLOBAL_CONFIG="$TEST_TMPDIR/none.json"
    . "$PROJECT_ROOT/lib/config.sh"
    . "$PROJECT_ROOT/commands/adopt.sh"
    cd "$TEST_TMPDIR"
}

adopt_json() {
    PVC_DRY_RUN=1 cmd_adopt "$@" 2>/dev/null | sed -n '/^{/,$p'
}

@test "adopt: builds lxc.json from an unprivileged legacy container" {
    json=$(adopt_json 117)
    [ "$(printf '%s' "$json" | jq -r .hostname)" = "strike" ]
    [ "$(printf '%s' "$json" | jq -r .ctid)" = "117" ]
    [ "$(printf '%s' "$json" | jq -r .storage)" = "ssd" ]
    [ "$(printf '%s' "$json" | jq -r .disk)" = "110G" ]
    [ "$(printf '%s' "$json" | jq -r .privileged)" = "false" ]
    [ "$(printf '%s' "$json" | jq -r .swap)" = "0" ]
    [ "$(printf '%s' "$json" | jq -r .dns)" = "192.168.1.10" ]
    [ "$(printf '%s' "$json" | jq -r .mount.source)" = "/data/app/navidrome/" ]
    [ "$(printf '%s' "$json" | jq -r .mount.target)" = "/mnt/navidrome" ]
}

@test "adopt: vlan tag, features and {ipv4} tag template" {
    json=$(adopt_json 201)
    [ "$(printf '%s' "$json" | jq -r .vlan)" = "20" ]
    [ "$(printf '%s' "$json" | jq -c .features)" = '{"nesting":true,"keyctl":true,"fuse":true}' ]
    [ "$(printf '%s' "$json" | jq -c .tags)" = '["{ipv4}","cloud"]' ]
}

@test "adopt: defaults for memory/swap left out of the conf, no empty fields" {
    json=$(adopt_json 250)
    [ "$(printf '%s' "$json" | jq -r .memory)" = "512" ]
    [ "$(printf '%s' "$json" | jq -r .swap)" = "512" ]
    [ "$(printf '%s' "$json" | jq 'has("cores")')" = "false" ]
    [ "$(printf '%s' "$json" | jq 'has("vlan")')" = "false" ]
    [ "$(printf '%s' "$json" | jq 'has("template")')" = "false" ]
}

@test "adopt: refuses to overwrite lxc.json without --force" {
    echo '{"ctid": 117}' > lxc.json
    run cmd_adopt 117
    [ "$status" -ne 0 ]
    [[ "$output" == *"--force"* ]]
}

@test "adopt: --force overwrites lxc.json" {
    echo '{"ctid": 1}' > lxc.json
    cmd_adopt 117 --force >/dev/null 2>&1
    [ "$(jq -r .ctid lxc.json)" = "117" ]
}

@test "adopt: rejects a template" {
    run cmd_adopt 9000
    [ "$status" -ne 0 ]
    [[ "$output" == *"template"* ]]
}

@test "adopt: unknown CTID fails" {
    run cmd_adopt 999
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "adopt: no container for the directory fails with a hint" {
    run cmd_adopt
    [ "$status" -ne 0 ]
    [[ "$output" == *"adopt <ctid>"* ]]
}
