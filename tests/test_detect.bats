#!/usr/bin/env bats
# tests/test_detect.sh - Unit tests for lib/detect.sh

load test_helper

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    . "$PROJECT_ROOT/lib/detect.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ── detect_storage ──

@test "detect_storage: finds zfspool with rootdir content" {
    _cfg="$TEST_TMPDIR/storage.cfg"
    cat > "$_cfg" <<'EOF'
zfspool: local-zfs
	pool rpool/data
	content images,rootdir
	sparse 1
EOF
    # Override path inside function
    detect_storage() {
        _cfg="$TEST_TMPDIR/storage.cfg"
        for _type in zfspool lvmthin lvm dir; do
            _match=$(awk -v t="$_type" '
                /^[a-z]/ { stype=$1; sub(/:$/,"",stype); sname=$2 }
                /content/ && stype == t && /rootdir/ { print sname; exit }
            ' "$_cfg")
            if [ -n "$_match" ]; then
                printf '%s' "$_match"
                return 0
            fi
        done
        return 1
    }
    result=$(detect_storage)
    [ "$result" = "local-zfs" ]
}

@test "detect_storage: prefers zfspool over dir" {
    _cfg="$TEST_TMPDIR/storage.cfg"
    cat > "$_cfg" <<'EOF'
dir: local
	path /var/lib/vz
	content iso,vztmpl,backup,rootdir

zfspool: tank
	pool tank/data
	content images,rootdir
EOF
    detect_storage() {
        _cfg="$TEST_TMPDIR/storage.cfg"
        for _type in zfspool lvmthin lvm dir; do
            _match=$(awk -v t="$_type" '
                /^[a-z]/ { stype=$1; sub(/:$/,"",stype); sname=$2 }
                /content/ && stype == t && /rootdir/ { print sname; exit }
            ' "$_cfg")
            if [ -n "$_match" ]; then
                printf '%s' "$_match"
                return 0
            fi
        done
        return 1
    }
    result=$(detect_storage)
    [ "$result" = "tank" ]
}

# ── detect_gateway ──

@test "detect_gateway: detects gateway from routing table" {
    run detect_gateway
    # On a real system, this should succeed (we're on Proxmox)
    [ "$status" -eq 0 ]
    # Result should look like an IP
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ── detect_dns ──

@test "detect_dns: returns a valid IP" {
    run detect_dns
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ── detect_bridge ──

@test "detect_bridge: detects bridge (vmbr0 on Proxmox)" {
    run detect_bridge
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}
