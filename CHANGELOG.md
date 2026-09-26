# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/).

## [1.2.0] - 2026-09-26

### Added

- **`pve-compose adopt`** (#3): brings an existing LXC under pve-compose management. It finds the
  container whose bind mount points at the current directory (or takes a CTID), reads
  `/etc/pve/lxc/<ctid>.conf` and writes a matching `lxc.json`. Handles trailing slashes, mounts
  in any `mpN` slot, nested directories, unprivileged containers and VLAN tags. `apply` right
  after adopting reports no changes. `--force` overwrites, `--dry-run` only prints.
- **VLAN support** (#5): `"vlan": 20` in `lxc.json` (or `defaults.vlan` in the global config)
  becomes `tag=20` on `net0`, on create, on clone and through `apply`. IDs are validated
  (1-4094), `"vlan": 0` removes a tag, and `plan` says whether the bridge is VLAN aware.
- `apply --yes` restarts without asking, for scripts and cron.
- `lib/resolve.sh`: shared parser for container configs.

### Changed

- **`down` shuts the LXC down** (#4) after `docker compose down`, since one LXC is one stack.
  Compose flags (`-v`, `--rmi`, ...) still go through first, the shutdown is graceful (forced
  after 60s) and `--keep-running` keeps the old behaviour. `up` starts it again through the
  fast path.
- `hostname` in `lxc.json` now wins over `basename $PWD` (`basename` stays the default).
- `plan` and `up` refuse to generate a new `lxc.json` in a directory that an existing container
  already mounts and point to `adopt`, instead of creating a second container on the same data.

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
- **`apply` changed the MAC address** (and dropped `firewall=1`) whenever the IP changed, because
  `net0` was rebuilt from scratch. It is now updated in place.
- **`apply` started stopped containers** after a restart-required change. A stopped container
  now stays stopped.
- **`confirm` crashed without a terminal** (`cannot open /dev/tty`, then an unset variable
  under `set -u`). It now answers no.

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
