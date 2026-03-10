# Architecture

Technical overview of pve-compose internals.

## Overview

pve-compose is a ~2,000 line POSIX shell project that orchestrates Docker Compose stacks inside Proxmox LXC containers. It's structured as an entry point with dynamic command dispatch, shared libraries, and one file per command.

### Design principles

- **POSIX shell only** - `#!/bin/sh`, `set -eu`, no bashisms. Runs on `dash` (Debian default)
- **Filesystem-first** - reads Proxmox config files directly instead of calling slow APIs
- **Lazy loading** - libraries are sourced only when needed by the current command
- **Zero state** - uses Proxmox's own config files as source of truth, no external state database
- **Convention over configuration** - detects everything, user overrides only what matters

## Directory structure

```
pve-compose/
├── bin/pve-compose                     # Entry point (107 lines)
├── lib/                                # Shared libraries (11 modules)
│   ├── output.sh                       # Terminal formatting, colors, die/msg/warn
│   ├── config.sh                       # JSON config parsing (jq)
│   ├── engine.sh                       # Resolution engine (config chain)
│   ├── detect.sh                       # Host auto-detection
│   ├── lxc.sh                          # LXC operations (filesystem + cgroup + lxc-attach)
│   ├── docker.sh                       # Docker lifecycle (check, install, wait, compose)
│   ├── compose.sh                      # Pass-through helper
│   ├── mount.sh                        # Bind mount configuration
│   ├── permissions.sh                  # Permission engine (passive)
│   ├── prompt.sh                       # Interactive prompts (whiptail TUI)
│   └── tags.sh                         # Tag template expansion
├── commands/                           # One file per command
│   ├── up.sh, plan.sh, destroy.sh ...  # 13 custom commands
│   ├── logs.sh, exec.sh, ps.sh ...     # 28 pass-through commands (~5 lines each)
│   └── template/                       # Template sub-commands
│       ├── create.sh, list.sh, remove.sh
├── scripts/
│   └── bootstrap-docker.sh             # Executed inside LXC to install Docker
├── completions/
│   └── pve-compose.bash                # Bash tab completion
├── debian/                             # .deb packaging
├── tests/                              # Test suite
└── Makefile                            # Build and install targets
```

## Entry point: `bin/pve-compose`

The entry point handles:

1. **Path resolution** - `readlink -f "$0"` to find `PVC_LIB` (works via symlink or direct execution)
2. **Library loading** - sources only `lib/output.sh` at startup
3. **Flag parsing** - `--debug`, `--dry-run`, `--version`, `--help`
4. **Command dispatch** - looks up `$PVC_LIB/commands/<cmd>.sh`, validates the command name (`[a-z0-9-]` only), sources it, and calls `cmd_<name>()`

```
pve-compose logs -f
  -> validates "logs" (safe chars only)
  -> sources commands/logs.sh
  -> calls cmd_logs("-f")
```

Zero business logic in the entry point - it's pure orchestration.

## Library modules

### `lib/output.sh` - Terminal output

Color-coded terminal output with TTY detection:

| Function | Output | Color |
|---|---|---|
| `die(msg)` | `✗ msg` + exit 1 | Red, stderr |
| `msg(msg)` | `✓ msg` | Green |
| `warn(msg)` | `⚠ msg` | Yellow, stderr |
| `info(msg)` | `ℹ msg` | Blue |
| `debug(msg)` | `[debug] msg` | Gray, stderr, only if `PVC_DEBUG=1` |
| `step(msg)` | `▸ msg` | Bold |
| `confirm(msg)` | `[y/N]` prompt | Reads from `/dev/tty` |

Colors are defined as literal escape strings (`'\033[0;31m'`). When output is not a terminal, all color variables are set to empty strings.

### `lib/config.sh` - Config parsing

JSON config reading via `jq`:

- `config_load_lxc_json()` - loads `lxc.json` from `$PWD`
- `config_load_global()` - loads `/etc/pve-compose/pve-compose.json`
- `config_get_field(FIELD, DEFAULT)` - resolves a field through the priority chain
- `config_write_lxc_json(JSON)` - writes a complete `lxc.json` preserving tag templates

### `lib/engine.sh` - Resolution engine

Core of pve-compose. Resolves all configuration through the priority chain:

```
lxc.json -> global config defaults -> auto-detection -> hardcoded fallbacks
```

Single function: `engine_resolve()` outputs a fully resolved JSON config. Called by `plan` and `up` (create path only - fast path skips it entirely).

Special rules:
- `privileged` resolves from lxc.json only (default: `true`)
- `features` derived from `privileged` (never set directly)
- `template` chain: lxc.json -> global `.template.ctid` -> OS tarball detection
- Tags expand `{var}` templates at deploy time

### `lib/lxc.sh` - LXC operations

Fast LXC operations using filesystem and cgroup checks instead of Proxmox API:

| Function | Method | Speed |
|---|---|---|
| `lxc_exists(CTID)` | `test -f /etc/pve/lxc/$ctid.conf` | ~0ms |
| `lxc_is_running(CTID)` | cgroup check + `lxc-info` fallback | 0-7ms |
| `lxc_wait_running(CTID)` | Poll cgroup after `pct start` | 0.1-1s |
| `lxc_exec(CTID, CMD)` | `lxc-attach -n $ctid -- CMD` | ~18ms |

Compare with Proxmox API equivalents:

| Operation | API method | Speed |
|---|---|---|
| Check existence | `pct status` | 1091ms |
| Execute command | `pct exec` | 989ms |

The `_pct_run()` wrapper handles `--dry-run` mode for all destructive `pct` operations.

### `lib/docker.sh` - Docker lifecycle

- `docker_ensure(CTID)` - idempotent: checks if Docker exists, installs if missing
- `docker_wait_ready(CTID)` - polls `docker info` until the daemon accepts connections (up to 30s). Required after container start because the Docker daemon needs 10-15s to initialize on first boot
- `docker_compose_exec(CTID, ARGS)` - auto-detects Compose V1 (`docker-compose`) vs V2 (`docker compose`) and executes with correct syntax

### `lib/compose.sh` - Pass-through helper

`compose_passthrough(CMD, ARGS)` - loads config, ensures container is running, forwards to `docker_compose_exec()`. Used by all 28 pass-through commands.

### `lib/prompt.sh` - Interactive prompts

TUI prompts using whiptail (pre-installed on Proxmox) with plain-text fallback:

- `prompt_input()` - text input
- `prompt_select()` - menu selection
- `prompt_password()` - hidden input
- `prompt_yesno()` - yes/no question
- `prompt_select_lines()` - dynamic menu from piped input

Falls back to plain `read` prompts when whiptail is absent or stdin is not a TTY.

### `lib/detect.sh` - Host detection

Reads host configuration from filesystem (not API) to avoid hangs with slow storage:

- `detect_storage()` - parses `/etc/pve/storage.cfg`, priority: zfspool > lvmthin > dir
- `detect_gateway()` - `ip route | grep default`
- `detect_dns()` - `/etc/resolv.conf`, skips localhost entries
- `detect_bridge()` - `ip link`, fallback `vmbr0`
- `detect_template()` - reads global config `.template.ctid`

### `lib/permissions.sh` - Permission engine

Passive module (never exposed as CLI). Called automatically by `plan` and `up`:

- `perm_pre_checks()` - validates mount source (exists, no symlinks, absolute path)
- `perm_post_validate(CTID)` - tests write access and Docker functionality
- `perm_diagnose(ERROR, CTID)` - maps errors to actionable diagnostics

## Command categories

| Category | Count | Pattern |
|---|---|---|
| Custom | 13 | Full command logic |
| Pass-through | 28 | 5 lines: source `compose.sh` + call `compose_passthrough()` |
| Template sub | 3 | Sub-dispatch via `commands/template.sh` |

### Pass-through pattern

Every pass-through command follows the same pattern:

```sh
#!/bin/sh
. "$PVC_LIB/lib/compose.sh"

cmd_logs() {
    compose_passthrough "logs" "$@"
}
```

### Sub-dispatch pattern

`commands/template.sh` dispatches to `commands/template/{create,list,remove}.sh` using the same pattern as the main entry point.

## Data flow: `pve-compose up -d`

```
pve-compose up -d
│
├── FAST PATH (container exists, < 0.5s):
│   config_load_lxc_json -> single-pass jq (~8ms)
│   test -f /etc/pve/lxc/$ctid.conf (~0ms)
│   lxc_is_running -> cgroup check (~0ms)
│   test -d mount_source (~0ms)
│   lxc-attach -> docker compose up -d (~230ms)
│
├── ZERO-CONFIG (no lxc.json):
│   check docker-compose.yml exists
│   engine_resolve -> auto-generate lxc.json
│   continue to CREATE PATH
│
└── CREATE PATH (new container, ~1-2 min):
    engine_resolve -> full config resolution
    lxc_clone or lxc_create
    mount_configure
    lxc_ensure_running + lxc_wait_running
    docker_ensure + docker_wait_ready (~10-15s)
    lxc-attach -> docker compose up -d
```

## External dependencies

| Tool | Purpose | Available on PVE |
|---|---|---|
| `jq` | JSON parsing | `apt install jq` |
| `pct` | LXC management | Native |
| `pvesh` | Proxmox API (CTID allocation only) | Native |
| `lxc-attach` | Fast command execution in containers | Native |
| `lxc-info` | Container state fallback | Native |
| `whiptail` | TUI menus (optional) | Pre-installed |

Zero runtime dependencies beyond Proxmox native tools + jq.
