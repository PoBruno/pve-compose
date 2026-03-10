# Templates

pve-compose templates are LXC containers with Docker pre-installed, converted to Proxmox templates. New services clone from the template instead of installing Docker from scratch.

## Why templates?

| Method | First deploy time |
|---|---|
| Without template | ~2-3 minutes (download OS + install Docker) |
| With template | ~10-15 seconds (clone + start) |

Templates are optional but highly recommended. You create one once, and every subsequent service benefits.

## Creating a template

```bash
pve-compose template create
```

Interactive wizard asks for:
- **Storage** - where to store the template
- **OS** - which Linux distribution (Debian 12 default)
- **Disk size** - rootfs size (8G default)
- **Name** - template name (`docker-base` default)
- **CTID** - template container ID (9000 default)

Non-interactive mode with auto-detected defaults:

```bash
pve-compose template create --non-interactive
```

Custom options:

```bash
pve-compose template create \
  --from debian-12-standard_12.0-1_amd64.tar.zst \
  --ctid 9001 \
  --name docker-base
```

### What happens during template creation

1. Downloads or locates a Linux OS template (Debian, Ubuntu, Alpine)
2. Creates an LXC container with Docker-compatible features (`nesting=1`)
3. Starts the container
4. Runs `scripts/bootstrap-docker.sh` inside it:
   - Installs `docker.io` and Docker Compose
   - Configures `daemon.json` (overlay2 storage driver, log rotation)
   - Enables Docker service
   - Cleans up package cache
5. Copies the host root password hash (same login as PVE)
6. Stops the container
7. Converts it to a Proxmox template (`pct template`)
8. Stores the template CTID in global config

## Listing templates

```bash
pve-compose template list
```

Shows all pve-compose templates with CTID, hostname, storage, and status.

## Removing a template

```bash
pve-compose template remove
```

Destroys the template and clears the reference from global config. The next `pve-compose up` (without a template in `lxc.json`) will fall back to creating from an OS tarball and installing Docker from scratch.

## How cloning works

When `pve-compose up` runs and a template is available:

```
Template (CTID 9000)
  │
  ├── pct clone 9000 210 --hostname immich
  ├── pct set 210 --memory 1024 --cores 1 ...
  ├── pct set 210 -mp0 /data/app/immich,mp=/data
  ├── pct start 210
  └── docker compose up -d    (Docker already installed)
```

### Linked vs full clone

| Scenario | Clone type | Speed |
|---|---|---|
| Template and target on same storage | Linked clone | Instant (ZFS CoW) |
| Template and target on different storage | Full clone | Slower (rsync) |

pve-compose auto-detects the storage match and uses the appropriate clone type.

## Template chain

When resolving which template to use, pve-compose follows this priority:

```
1. lxc.json "template" field          -> explicit template (CTID or tarball)
2. Global config "template.ctid"      -> template created by `template create`
3. Auto-detect OS tarball on disk     -> vanilla Debian/Ubuntu (installs Docker)
```

If no template is available at all, pve-compose downloads a Debian image automatically.

## Supported OS distributions

Templates can be built from any Linux distribution supported by Proxmox:

| Distribution | Docker support | Notes |
|---|---|---|
| Debian 12 (Bookworm) | Docker Compose V1 | Default, recommended |
| Debian 13 (Trixie) | Docker Compose V2 | Newer Docker engine |
| Ubuntu 22.04/24.04 | Docker Compose V2 | Full support |
| Alpine | Docker Compose (apk) | Minimal footprint |

The bootstrap script (`scripts/bootstrap-docker.sh`) auto-detects the distribution and uses the appropriate package manager.
