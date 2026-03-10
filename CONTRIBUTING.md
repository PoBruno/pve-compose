# Contributing

Contributions are welcome. This document explains how to get started.

## Requirements

- Proxmox VE 8+ host (for testing)
- `jq` installed on the host
- `shellcheck` for linting
- `bats` for functional tests (optional)

## Development Setup

```bash
# Clone the repo
git clone https://github.com/PoBruno/pve-compose.git
cd pve-compose

# Symlink for development
ln -sf "$PWD/bin/pve-compose" /usr/local/bin/pve-compose

# Verify it works
pve-compose version
```

## Project Structure

```
bin/pve-compose      # Entry point (dispatch)
lib/                 # Shell libraries (sourced by entry point)
commands/            # One file per command
commands/template/   # Template sub-commands
scripts/             # Scripts executed inside LXC containers
```

See [docs/architecture.md](docs/architecture.md) for full details.

## Code Conventions

- **Shell**: POSIX (`#!/bin/sh`, `set -eu`). No bashisms
- **JSON**: `jq` only. Never parse JSON with grep/sed/awk
- **Variables**: always quoted (`"$var"`)
- **Errors**: write to stderr (`>&2`), use meaningful exit codes
- **Functions**: prefix when risk of collision (`lxc_`, `docker_`, `config_`)
- **Libraries**: define functions only - no execution at source time
- **Command check**: `command -v` instead of `which`

## Linting

Every script must pass shellcheck with zero warnings:

```bash
# Check a single file
shellcheck -s sh lib/config.sh

# Check everything
make lint
```

## Testing

```bash
# Run all tests
make test

# Run a specific test file
bats tests/test_config.sh
```

## Building the .deb Package

```bash
make deb
# Output: pve-compose_0.1.0-1_all.deb
```

## Adding a New Command

1. Create `commands/mycommand.sh`
2. Add a help entry in `commands/help.sh`
3. If it's a pass-through command (forwarded to `docker compose`), use `lib/passthrough.sh`
4. If it's a custom command, implement the logic directly
5. Run `shellcheck -s sh commands/mycommand.sh`
6. Test on a real Proxmox host

## Adding a New Library

1. Create `lib/mylib.sh` with only function definitions
2. Source it in `bin/pve-compose`
3. Prefix functions to avoid collisions
4. Run `shellcheck -s sh lib/mylib.sh`

## Submitting Changes

1. Fork the repository
2. Create a branch (`feature/my-feature` or `fix/my-fix`)
3. Make your changes following the conventions above
4. Run `make lint` - must pass with zero warnings
5. Test on a real Proxmox host
6. Submit a pull request with a clear description

## Reporting Issues

When reporting bugs, include:

- Proxmox VE version (`pveversion`)
- pve-compose version (`pve-compose version`)
- The command you ran
- The full error output
- Your `lxc.json` (if relevant)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
