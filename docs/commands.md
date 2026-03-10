# Commands Reference

Complete reference for every pve-compose command.

## Global Options

```
--debug       Enable debug output (shows internal commands)
--dry-run     Show what would be done without executing
--version     Show version and exit
--help        Show help and exit
```

## Setup Commands

### `pve-compose setup`

Configure global defaults at `/etc/pve-compose/pve-compose.json`. Auto-detects storage, network, DNS, and bridge from your Proxmox host.

```bash
pve-compose setup                     # interactive wizard (whiptail TUI)
pve-compose setup --non-interactive   # auto-detect everything
pve-compose setup --force             # overwrite existing config
```

### `pve-compose init`

Create global config with auto-detected defaults. Alias for initial setup.

```bash
pve-compose init
```

### `pve-compose template create`

Create an LXC template with Docker pre-installed. Subsequent `up` commands clone from this template (~10s) instead of installing Docker from scratch (~2-3 min).

```bash
pve-compose template create                                          # interactive wizard
pve-compose template create --from debian-12-standard_12.0-1_amd64.tar.zst   # specific OS
pve-compose template create --ctid 9001 --name my-docker-base        # custom CTID and name
pve-compose template create --non-interactive                        # auto defaults
```

### `pve-compose template list`

List available pve-compose templates.

```bash
pve-compose template list
```

### `pve-compose template remove`

Remove an existing template.

```bash
pve-compose template remove
```

## Lifecycle Commands

### `pve-compose plan`

Resolve configuration and generate `lxc.json`. Dry-run - shows what `up` would use without creating anything.

```bash
cd /data/app/myservice
pve-compose plan
# -> generates lxc.json with all fields resolved
```

### `pve-compose up`

Create LXC container, install Docker, configure mounts, and run `docker compose up`. If the container already exists, goes through the fast path (< 0.5s).

```bash
pve-compose up -d          # detached (recommended)
pve-compose up             # foreground (shows compose output)
pve-compose up --build     # rebuild images before starting
```

All flags after `up` are forwarded to `docker compose up`.

**Fast path**: When the container already exists and is running, `up` skips all resolution and just runs `docker compose up` directly via `lxc-attach`. Budget: ~230ms.

**Zero-config**: If no `lxc.json` exists, `up` auto-generates one from detected defaults and saves it.

### `pve-compose down`

Stop and remove Docker Compose services (containers, networks). The LXC container remains.

```bash
pve-compose down
pve-compose down -v        # also remove volumes
```

### `pve-compose destroy`

Stop compose services, stop the LXC container, and destroy it. Asks for confirmation.

```bash
pve-compose destroy
pve-compose destroy --force   # skip confirmation
```

Does **not** remove `lxc.json` or `docker-compose.yml`.

## Operations Commands

### `pve-compose status`

Show combined LXC container info and Docker Compose service status.

```bash
pve-compose status
```

Output:

```
Container
  CTID:      100
  Hostname:  speedtest
  Status:    running
  IP:        192.168.1.54

Compose
NAME        IMAGE                         STATUS         PORTS
speedtest   linuxserver/speedtest-tracker  Up 2 hours     8080->80/tcp
```

### `pve-compose doctor`

Run 10 diagnostic checks on the current project:

```bash
pve-compose doctor
```

Checks:

1. `lxc.json` exists and is valid JSON
2. CTID defined and container exists
3. Container is running
4. Docker installed (shows version)
5. Docker Compose available (V1 or V2)
6. Bind mount accessible (read/write test)
7. `docker-compose.yml` found in mount point
8. Compose config valid (`docker compose config --quiet`)
9. Nesting enabled
10. Disk usage (green < 90%, yellow 90-95%, red > 95%)

Exit code 0 if all pass, 1 if any fail.

### `pve-compose apply`

Compare `lxc.json` with the actual container config and apply differences.

```bash
# Edit lxc.json first
nano lxc.json

# Apply changes
pve-compose apply
```

**Hot-apply** (no restart needed): `memory`, `swap`, `cores`, `cpulimit`, `tags`, `dns`, `description`

**Restart required**: `hostname`, `features`, `net0` (IP, bridge, gateway)

If restart-required changes are detected, `apply` asks for confirmation before restarting.

### `pve-compose shell`

Open an interactive shell inside the LXC container.

```bash
pve-compose shell
```

### `pve-compose overview`

List Docker containers across all running LXCs on the host.

```bash
pve-compose overview         # default: running containers only
pve-compose overview -a      # include stopped containers
```

### `pve-compose version`

```bash
pve-compose version
pve-compose --version
```

## Docker Compose Pass-through Commands

These commands are forwarded directly to `docker compose` inside the LXC container. All flags and arguments are passed through as-is.

| Command | Description |
|---|---|
| `attach` | Attach to a running service container |
| `build` | Build or rebuild services |
| `commit` | Create image from container changes |
| `config` | Validate and view the compose file |
| `cp` | Copy files between container and host |
| `create` | Create containers without starting |
| `down` | Stop and remove containers, networks |
| `events` | Receive real-time container events |
| `exec` | Execute a command in a running container |
| `export` | Export container filesystem as tar |
| `images` | List images used by services |
| `kill` | Force stop service containers |
| `logs` | View output from containers |
| `ls` | List running compose projects |
| `pause` | Pause services |
| `port` | Print public port for a port binding |
| `ps` | List containers |
| `pull` | Pull service images |
| `push` | Push service images |
| `restart` | Restart service containers |
| `rm` | Remove stopped service containers |
| `run` | Run a one-off command on a service |
| `scale` | Scale services |
| `start` | Start services |
| `stats` | Display live resource usage |
| `stop` | Stop services |
| `top` | Display running processes |
| `unpause` | Unpause services |
| `wait` | Block until containers stop |
| `watch` | Watch build context for changes |

### Examples

```bash
pve-compose logs -f                    # follow all logs
pve-compose logs -f --tail 100 app     # follow app service, last 100 lines
pve-compose exec -it app bash          # shell into app service
pve-compose ps -a                      # list all containers (including stopped)
pve-compose pull                       # pull latest images
pve-compose restart                    # restart all services
pve-compose images                     # list images
pve-compose top                        # show processes
pve-compose stats                      # live CPU/memory usage
```
