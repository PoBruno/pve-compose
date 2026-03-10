# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] - 2026-03-10

First public release.

### Added

- **CLI entry point** with dynamic command dispatch
- **13 custom commands**: `setup`, `init`, `plan`, `up`, `down`, `destroy`, `status`, `doctor`, `apply`, `shell`, `overview`, `version`, `help`
- **28 pass-through commands**: `exec`, `logs`, `ps`, `pull`, `restart`, `start`, `stop`, `top`, `images`, `build`, `run`, `rm`, `kill`, `pause`, `unpause`, `events`, `port`, `config`, `ls`, `cp`, `export`, `push`, `commit`, `attach`, `wait`, `watch`, `scale`, `stats`
- **Template management**: `template create`, `template list`, `template remove` with linked clone support
- **Zero-config deployment** - run `pve-compose up -d` with just a `docker-compose.yml`
- **Fast path optimization** - filesystem + cgroup + lxc-attach (status in ~300ms, was 11s+)
- **Interactive TUI** - whiptail wizard for OS, hostname, storage, CTID selection
- **Bash completion** - tab completion for all commands and options
- **Doctor checks** - validates Docker, Compose, mount, DNS, container state
- **Apply command** - detects and applies lxc.json changes to running containers
- **Config resolution chain** - lxc.json -> global config -> smart defaults
- **Docker Compose V1/V2 auto-detection**
- **DNS localhost filtering** - removes 127.* nameservers for LXC safety
- **Docker daemon wait** - polls up to 30s for Docker readiness after container start
- **Tag templates** - clone from pre-configured templates instead of OS tarballs
- **.deb packaging** - `make deb` builds a Debian package
- **11 library modules**: config, lxc, docker, passthrough, compose_file, pct_helpers, id, global, template, setup, tui
- **65+ scripts** - all POSIX-clean, zero shellcheck warnings
