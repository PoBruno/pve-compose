# Troubleshooting

Common issues and how to fix them.

## `pve-compose doctor`

The fastest way to diagnose problems:

```bash
cd /data/app/myservice
pve-compose doctor
```

Output example:

```
✓ lxc.json valid (ctid: 100)
✓ Container 100 exists
✓ Container 100 is running
✓ Docker installed (26.1.5)
✓ Docker Compose 2.24.5
✓ Mount /data accessible (read/write)
✓ docker-compose.yml found
✓ Compose config valid
✓ Nesting enabled
✓ Disk usage 35% (0.7G/2.0G)

All checks passed.
```

## Common issues

### "Container not found" or "lxc.json not found"

You're not in the right directory. pve-compose uses `$PWD` as context:

```bash
cd /data/app/myservice    # directory with docker-compose.yml
pve-compose status        # now it works
```

### "Cannot connect to the Docker daemon"

Docker daemon isn't ready yet. This happens on first boot after cloning a template.

**Fix**: Wait a few seconds and try again. pve-compose's `up` command handles this automatically with `docker_wait_ready()` (polls for up to 30 seconds).

If it persists inside the container:

```bash
pve-compose shell
systemctl status docker
systemctl start docker
```

### Docker Compose command not found

The container might have Docker Compose V1 (Debian 12) or V2 (Debian 13). pve-compose auto-detects both.

If neither is found:

```bash
pve-compose shell
apt update && apt install docker-compose-plugin
```

### Permission denied on bind mount

The host directory might not be accessible from the container.

```bash
# Check mount is configured
pve-compose doctor

# Verify the source directory exists
ls -la /data/app/myservice/

# Check container config
cat /etc/pve/lxc/<CTID>.conf | grep mp0
```

For privileged containers (default), permissions are straightforward - root inside the container maps to root on the host.

### Clone fails with "Lost 'create' config lock"

This is a known PVE bug with full clones on ZFS. pve-compose works around this by using **linked clones** when source and destination storage are the same.

If you hit this error:

```bash
# Destroy the failed container
pct destroy <CTID> --force

# Retry - pve-compose should auto-select linked clone
pve-compose up -d
```

### `pvesh` or `pct config` hangs

This happens when a Proxmox host has CIFS/NFS storage that's offline or unreachable.

pve-compose avoids this by reading config files directly from `/etc/pve/` instead of calling `pvesh` or `pct config`. If you still experience hangs:

```bash
# Check which storage is problematic
pvesm status

# Disable or remove the offline storage in the Proxmox UI
```

### DNS not working inside LXC

Your host's `/etc/resolv.conf` might point to `127.0.0.1` (Pi-hole, AdGuard, systemd-resolved). This address doesn't work inside LXC containers.

pve-compose auto-detects this and skips localhost DNS entries. To fix manually:

```bash
# Edit lxc.json
nano lxc.json
# Set "dns": "1.1.1.1" or your actual DNS server

pve-compose apply
```

### Disk space full inside container

```
✗ Disk usage 97% (7.8G/8G)
```

The container rootfs is only for the OS and Docker images. Data should live on the bind mount. If rootfs is full:

```bash
# Clean Docker cache
pve-compose exec -- docker system prune -af

# Or increase disk size in lxc.json
nano lxc.json    # change "disk": "16G"
pve-compose apply
```

### Container starts but `up -d` produces no output

This is normal for detached mode. Check status:

```bash
pve-compose ps
pve-compose logs
```

### `pve-compose up` creates a new container every time

Make sure `lxc.json` is persisted in the project directory. After the first `up`, an `lxc.json` is created with the container ID. If this file is deleted, `up` will create a new container.

### Slow `pve-compose overview`

The `overview` command queries Docker across all running LXCs. Each `docker ps` call takes ~200ms via `lxc-attach`. With 8 containers, expect ~2 seconds. This is normal - it's running a command inside each container sequentially.

## Debug mode

For detailed output of what pve-compose is doing:

```bash
pve-compose --debug up -d
```

Shows every internal command being executed.

## Dry-run mode

See what would happen without executing anything:

```bash
pve-compose --dry-run up -d
```

Shows the `pct` commands that would be run.

## Getting help

```bash
pve-compose --help                # general help
pve-compose help <command>        # per-command help
pve-compose help up
pve-compose help doctor
```
