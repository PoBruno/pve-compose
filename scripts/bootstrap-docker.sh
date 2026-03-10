#!/bin/sh
# scripts/bootstrap-docker.sh - Install Docker inside an LXC container
# Executed via: pct exec <CTID> -- sh < scripts/bootstrap-docker.sh
# Supports: Debian/Ubuntu (apt) and Alpine (apk)
set -eu

# Detect distro
detect_distro() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        printf '%s' "$ID"
    elif [ -f /etc/alpine-release ]; then
        printf 'alpine'
    else
        printf 'unknown'
    fi
}

install_debian() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq

    # Install docker engine
    apt-get install -y -qq docker.io >/dev/null 2>&1

    # Install compose: try plugin first, fall back to standalone
    if apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1; then
        : # docker-compose-plugin installed (Docker official repo)
    elif apt-get install -y -qq docker-compose >/dev/null 2>&1; then
        : # docker-compose standalone installed (Debian default repo)
    else
        printf 'Warning: docker-compose not found in repositories\n' >&2
    fi

    # Configure daemon.json
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'DAEMON'
{
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
DAEMON

    systemctl enable docker
    systemctl start docker

    # Cleanup
    apt-get clean
    rm -rf /var/lib/apt/lists/*
}

install_alpine() {
    apk update --quiet
    apk add --quiet docker docker-cli-compose

    # Configure daemon.json
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'DAEMON'
{
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
DAEMON

    rc-update add docker default
    service docker start
}

# ── Main ──
_distro=$(detect_distro)
printf 'Detected distro: %s\n' "$_distro"

case "$_distro" in
    debian|ubuntu)
        install_debian
        ;;
    alpine)
        install_alpine
        ;;
    *)
        printf 'Unsupported distro: %s\n' "$_distro" >&2
        exit 1
        ;;
esac

# Verify
if command -v docker >/dev/null 2>&1; then
    printf 'Docker installed: %s\n' "$(docker --version)"
else
    printf 'Docker installation failed\n' >&2
    exit 1
fi
