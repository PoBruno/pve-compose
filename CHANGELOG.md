# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [1.1.1] - 2026-09-26

Bug-fix release: several `lxc.json` fields were silently ignored.

### Fixed

- **`up`: requested disk size ignored on clone** - containers cloned from a template kept the
  template's rootfs size (e.g. 2G) because `pct clone` has no size option. The rootfs is now
  grown to `disk` right after cloning (grow only; a smaller value only warns).
- **`apply` ignored `disk`, `mount`, `storage` and `template`** while printing "Changes applied".
  It now grows the rootfs online, configures the bind mount, and warns on storage/template
  changes (which need a manual `pct move-volume` / recreate).
- **Disk units**: `"512M"` no longer becomes 512 GB; non-whole-GB sizes are rejected with a
  clear message.
- **Readable validation**: `ctid`, `cores`, `memory`, `swap` and `privileged` are validated
  instead of failing with a raw `jq --argjson` parse error (e.g. `"2048MB"`).
- **`"swap": 0`** is preserved instead of falling back to the 512 default.
- **`features`**: the whole object is honoured (`nesting: false` was ignored) and keys are
  order-normalized, so `apply` no longer reports a phantom diff.
- **Mount slots**: a free `mpN` slot is used instead of always overwriting `mp0`.
- **`lxc_wait_running`** counted 0.1s sleeps as 1s (timeout 100 waited 10s).
- **CTID race**: the CTID is re-checked right before `pct create`.

## [1.1.0] - 2026-03-10

### Changed

- Maintainer and copyright set to Bruno Poleza Gomes across packaging and docs.
- `.deb` now suggests `bash-completion` (required for tab completion to load).

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
