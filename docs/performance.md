# Performance

Benchmarks and design decisions behind pve-compose's performance optimizations. All measurements taken on Proxmox VE 8.4, kernel 6.8.12, ZFS storage, cgroupv2 unified.

## Summary

| Command | Time | Notes |
|---|---|---|
| `pve-compose version` | 3ms | No libraries loaded |
| `pve-compose help` | 10ms | Minimal library loading |
| `pve-compose template list` | 70ms | Filesystem scan |
| `pve-compose logs` | 220ms | lxc-attach + docker compose |
| `pve-compose images` | 220ms | lxc-attach + docker compose |
| `pve-compose up -d` (fast path) | 260ms | Container already running |
| `pve-compose status` | 310ms | LXC info + compose ps |
| `pve-compose doctor` | 330ms | 10 checks via lxc-attach |
| `pve-compose ps` | 480ms | lxc-attach + docker compose ps |
| `pve-compose up -d` (create path) | 1-2 min | Clone + Docker install + image pull |

## Benchmark: `lxc-attach` vs `pct exec`

```
lxc-attach -n 214 -- echo ok       ->   18ms
pct exec 214 -- echo ok            ->  989ms
```

**55x faster.** `pct exec` is a Perl wrapper that calls the Proxmox API, which internally calls `lxc-attach`. We skip the Perl/API overhead entirely.

Used everywhere commands run inside containers: `docker compose`, `docker info`, bootstrap scripts.

## Benchmark: filesystem vs `pct status`

```
test -f /etc/pve/lxc/214.conf      ->    0ms
pct status 214                      -> 1091ms
```

**~1000x faster.** Proxmox stores LXC configs in `/etc/pve/lxc/` via pmxcfs (FUSE-based cluster filesystem). Reading a file is instantaneous. `pct status` goes through the Perl API stack.

Used for container existence checks in the fast path.

## Benchmark: cgroup vs `pct status` for running state

```
test -d /sys/fs/cgroup/lxc/214     ->    0ms
lxc-info -n 214 -sH                ->    7ms  (fallback)
pct status 214                     -> 1091ms
```

The cgroup directory `/sys/fs/cgroup/lxc/$CTID` exists **only** when the container is running (verified on PVE 8.x with cgroupv2 unified). This is the kernel's own state - always accurate, zero overhead.

`lxc-info` serves as a portable fallback for hosts with different cgroup layouts (PVE 7.x, custom systemd slices).

## Fast path design

The hot path for `pve-compose up -d` when the container already exists:

```
1. config_load_lxc_json        -> single jq call          ~8ms
2. test -f $ctid.conf          -> filesystem check         ~0ms
3. test -d cgroup/$ctid        -> cgroup check             ~0ms
4. test -d mount_source        -> mount available           ~0ms
5. lxc-attach -> docker compose -> actual work            ~230ms
                                              TOTAL      ~240ms
```

Before M12 optimization, the same operation took **~11 seconds** because it ran `pct status` (1091ms), `pct exec` (989ms × 2-3 calls), and the full `engine_resolve` chain.

### What the fast path skips

When the container already exists, these are completely skipped:
- `engine_resolve()` - the full resolution chain (storage, network, template detection)
- `detect_*()` functions - host auto-detection
- `docker_ensure()` - Docker installation check
- `pct` API calls - no Perl overhead
- `pvesh` calls - no API overhead

### Budget breakdown

| Phase | CT running | CT stopped |
|---|---|---|
| Config load (jq) | 8ms | 8ms |
| Existence check | 0ms | 0ms |
| Running check | 0ms | 0ms |
| Container start | - | ~1-2s |
| Wait for cgroup | - | 0.1-1s |
| Docker wait | - | 10-15s |
| Mount check | 0ms | 0ms |
| lxc-attach + compose | ~230ms | ~230ms |
| **Total** | **~240ms** | **~12-18s** |

## Why filesystem reads instead of API calls

### `pvesh` can hang

When a Proxmox host has CIFS/NFS storage that's offline or slow, `pvesh` API calls (which enumerate all storages) can hang for 30+ seconds or indefinitely.

Our solution: read `/etc/pve/storage.cfg` and `/etc/pve/lxc/*.conf` directly. These files are served by pmxcfs and are always available regardless of storage health.

### `pct config` can be slow

`pct config <CTID>` on containers with CIFS mount points can take 10+ seconds. Iterating `pct config` over all containers (as in `overview`) would be catastrophically slow.

Our solution: read `/etc/pve/lxc/<CTID>.conf` directly with `grep` and `awk`. Instantaneous.

## Docker daemon startup wait

After `pct start` on a freshly cloned container, the Docker daemon needs 10-15 seconds to initialize (first boot, systemd startup, overlay2 setup).

Without waiting, `docker compose up -d` fails with:

```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock
```

Solution: `docker_wait_ready()` polls `docker info` every 0.2s for up to 30 seconds (150 attempts). Returns as soon as the daemon responds.

```
pct start 214                     -> immediate return
docker_wait_ready(214)            -> polls until daemon ready (~10-15s on first boot)
docker compose up -d              -> works
```

On subsequent starts (warm boot), the daemon is ready in 1-2 seconds.

## Container startup wait

After `pct start`, there's a brief window where the cgroup directory hasn't been created yet and `lxc-attach` would fail.

Solution: `lxc_wait_running()` polls the cgroup directory every 0.1s with a 10s timeout. Typically resolves in 0.1-1s.

## Docker Compose V1 vs V2 auto-detection

```
Debian 12 (Bookworm): docker-compose V1 standalone
Debian 13 (Trixie):   docker compose V2 plugin
```

`docker_compose_exec()` tries `docker compose version` first. If that fails, falls back to `command -v docker-compose`. Transparent to the user - all compose commands work regardless of version.

## Single-pass jq in the fast path

The fast path needs two values from `lxc.json`: `ctid` and `mount.target`. Instead of two `jq` calls:

```sh
# Slow: 2 jq processes (~16ms)
_ctid=$(jq -r '.ctid' lxc.json)
_mount=$(jq -r '.mount.target' lxc.json)
```

We use one:

```sh
# Fast: 1 jq process (~8ms)
eval "$(jq -r '"_ctid=\(.ctid) _mount=\(.mount.target // "/data")"' lxc.json)"
```

Small optimization, but every millisecond counts on the hot path.

## Clone strategy: linked vs full

```
Same storage (src -> dst):      linked clone  ->  instant (ZFS CoW)
Different storage (src -> dst): full clone    ->  rsync-based, slower
```

Linked clones on ZFS use copy-on-write - the new container shares blocks with the template until modified. Nearly instant and space-efficient.

Full clones with `--full` on ZFS can fail with a PVE locking bug ("Lost 'create' config lock"). Linked clones don't have this issue.

pve-compose auto-detects: if source and destination storage are the same, use linked clone. Otherwise, full clone with `--full --storage`.

## I/O: LXC vs VM vs bare metal

| Environment | Type | IOPS (ZFS) |
|---|---|---|
| VM (KVM) | Hardware virtualization | ~6,800 (zvol) |
| LXC | Shared kernel | ~18,000 (subvol) |
| Bare metal | Direct | ~18,000 (ZFS) / ~84,000 (raw) |

LXC containers share the host kernel - no hypervisor overhead. I/O performance is identical to bare metal on the same filesystem.
