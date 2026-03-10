# FAQ

## Why LXC instead of VMs?

LXC containers share the host kernel. Compared to VMs:

- **Startup**: ~1-2 seconds vs ~30-60 seconds
- **Memory**: shared kernel, no hypervisor overhead
- **I/O**: native filesystem access (~18,000 IOPS on ZFS vs ~6,800 for VM zvols)
- **Density**: run 20+ services on a single node with minimal overhead

LXC gives you the isolation of separate Linux systems with the performance of bare metal.

## Why not run Docker directly on the Proxmox host?

You can, but you lose:

- **Isolation** - one broken service can take down everything
- **Independent backups** - Proxmox `vzdump` backs up each LXC separately
- **Resource limits** - each LXC has its own memory/CPU limits
- **Independent restarts** - restart one service without affecting others
- **Clean separation** - each service has its own filesystem, network, and process tree

With pve-compose, each `docker-compose.yml` gets its own container. The concept is **1 LXC = 1 Compose stack**.

## Why POSIX shell instead of Go/Python/Rust?

pve-compose orchestrates CLI tools (`pct`, `lxc-attach`, `docker compose`). Shell does this natively:

- **Zero dependencies** - runs on any Proxmox host out of the box (just add `jq`)
- **Trivial deployment** - single `dpkg -i` or `curl` download
- **Proxmox ecosystem fit** - Proxmox itself is managed via shell tools. The entire [tteck helper scripts](https://github.com/tteck/Proxmox) ecosystem is shell
- **Transparent** - you can read every line of code and understand exactly what it does
- **No build step** - edit a file, it's live

For a tool that wraps other CLIs, shell is the right level of abstraction. If pve-compose needed a web UI, REST API, or concurrent operations, Go would make sense. For orchestrating sequential CLI calls, shell is simpler and faster to develop.

## Is this production-ready?

pve-compose v0.1.0 is stable for home labs and small deployments. It has been tested end-to-end across the full lifecycle:

- Setup -> template create -> plan -> up -> status -> doctor -> exec -> logs -> apply -> down -> destroy
- 65+ scripts pass `shellcheck` with zero warnings
- All 41 commands (13 custom + 28 pass-through) tested on real Proxmox host

For production use, evaluate your requirements around high availability, clustering, and automated failover - these are not in scope for v0.1.0.

## Does it work with Proxmox clusters?

pve-compose operates on a single node. The config files (`/etc/pve/lxc/*.conf`) are available cluster-wide via pmxcfs, but the tool runs `pct` and `lxc-attach` locally.

For multi-node setups, run pve-compose on each node separately. Migration support is not yet implemented.

## Can I use unprivileged containers?

Yes. Set `"privileged": false` in `lxc.json`. pve-compose automatically adjusts the LXC features:

- Privileged (`true`): `nesting=1`
- Unprivileged (`false`): `nesting=1,keyctl=1`

The default is privileged because it simplifies Docker setup (no UID/GID mapping issues). For trusted home lab environments, this is reasonable. For multi-tenant or exposed systems, consider unprivileged.

## What about GPU passthrough?

Not currently supported. GPU passthrough in LXC requires manual configuration of device mounts and cgroup rules that vary by hardware. This may be added in a future version.

## Which Docker Compose versions are supported?

Both:

- **V1** - `docker-compose` standalone binary (Debian 12)
- **V2** - `docker compose` CLI plugin (Debian 13+, Ubuntu 22.04+)

pve-compose auto-detects which is available and uses the correct syntax. No user configuration needed.

## Can I use a custom Docker Compose filename?

pve-compose currently expects `docker-compose.yml` (or `docker-compose.yaml`, `compose.yml`, `compose.yaml`). These are detected by Docker Compose itself - pve-compose passes `--project-directory` and lets Docker Compose find the file.

## How does backup work?

Use standard Proxmox backup:

```bash
vzdump <CTID> --storage backup-storage
```

This backs up the entire LXC container including Docker images and container state. The bind-mounted host directory is **not** included in the backup - back that up separately with your preferred tool.

## How do I update Docker images?

```bash
cd /data/app/myservice
pve-compose pull        # pull latest images
pve-compose up -d       # recreate with new images
```

## Can I access the container directly via Proxmox?

Yes. pve-compose containers are standard Proxmox LXC containers. You can:

- View them in the Proxmox web UI
- Open a console from the UI
- Manage them with `pct` commands directly
- Configure resources and networking from the UI

pve-compose doesn't lock you in - it's just a convenience layer.

## Where is the source of truth for container state?

Proxmox itself. pve-compose reads:

- `/etc/pve/lxc/<CTID>.conf` - container configuration (via pmxcfs)
- `/sys/fs/cgroup/lxc/<CTID>/` - running state (kernel)
- `lxc.json` - only for initial creation and apply

There's no external database or state file. If you modify the container through the Proxmox UI, pve-compose sees the changes.
