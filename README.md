# pve-compose

**One Docker Compose stack per LXC on Proxmox. The folder is the stack, the storage is the backup.**

## Why

I run my homelab on a single Proxmox box. Every app lives in its own folder on a ZFS pool
(`/data/app/immich`, `/data/app/n8n`, ...), with its `docker-compose.yml` and all of its data
next to it. Each app gets its own LXC, so it has its own IP, RAM limit and restart, and one
broken stack never takes the others down. Backup is just cloning the disk: every compose file,
config and database is in there.

Doing that by hand meant the same routine for every app: create the CT, enable nesting, bind
mount the folder, install Docker, `pct exec` into it to run compose, and remember which CTID
belongs to which folder. pve-compose turns all of that into one command, run from the folder:

```bash
cd /data/app/immich
pve-compose up -d
```

## How it works

```
/data/app/immich/            host storage (ZFS, LVM, anything Proxmox manages)
├── docker-compose.yml       volumes as ./relative paths, so the data stays here
├── lxc.json                 the container: CTID, IP, RAM, disk (generated, editable)
└── library/  postgres/      app data
        │
        │ bind mount -> /data
        ▼
LXC 200 "immich"  ->  docker compose up -d
```

- `$PWD` is the context. Every command works on the stack of the folder you are in.
- The LXC is disposable. Destroy it, run `up` again, same app with the same data.
- Copy the folder to another Proxmox host and `up` it there: same stack.
- Plain POSIX `sh` + `jq`, nothing else to install.

## Install

```bash
curl -sL https://github.com/PoBruno/pve-compose/releases/latest/download/pve-compose_all.deb \
  -o /tmp/pve-compose.deb && dpkg -i /tmp/pve-compose.deb

pve-compose setup              # detects storage, bridge, gateway, DNS
pve-compose template create    # optional: Docker-ready template, new CTs clone in ~10s
```

Proxmox VE 7 or newer (tested on 9.1) and `jq`. From source: `make install`.

## Use

```bash
mkdir -p /data/app/speedtest && cd /data/app/speedtest
cat > docker-compose.yml <<'EOF'
services:
  speedtest:
    image: lscr.io/linuxserver/speedtest-tracker:latest
    ports: ["8080:80"]
    volumes: ["./config:/config"]
EOF

pve-compose up -d        # creates the LXC, mounts the folder, installs Docker, compose up
pve-compose logs -f
```

Want a fixed IP or more RAM? `pve-compose plan` writes `lxc.json`, edit it, then `up`
(new container) or `apply` (existing one).

Already have containers you set up by hand? `cd` into the folder they mount and run
`pve-compose adopt`. It reads the container config and writes `lxc.json`, without touching
the container.

## Commands

| Command | What it does |
|---|---|
| `up -d` | Create the LXC if needed, then `docker compose up` (under a second if it already runs) |
| `down` | `compose down`, then shut the LXC down. `--keep-running` to leave it on |
| `plan` | Resolve the config and write `lxc.json` without creating anything |
| `apply` | Push `lxc.json` changes to the container: RAM, CPU, disk, IP, VLAN, mount |
| `adopt [ctid]` | Generate `lxc.json` from an existing container |
| `status` / `doctor` | Container and compose status / 10 health checks |
| `shell` | Shell inside the LXC |
| `destroy` | Compose down and destroy the LXC. The folder stays |
| `overview` | Docker containers across all LXCs |
| `setup` / `template` | Global defaults / Docker-ready template |

Any other compose command goes straight to the container: `logs`, `exec`, `ps`, `pull`,
`restart`, `build`, `run`, `stop`, `top` and the rest. Global flags: `--dry-run`, `--debug`.

## lxc.json

```json
{
  "hostname": "immich",
  "ctid": 200,
  "template": "9000",
  "storage": "local-zfs",
  "disk": "20G",
  "cores": 2,
  "memory": 4096,
  "ipv4": "192.168.1.200/24",
  "gateway": "192.168.1.1",
  "bridge": "vmbr0",
  "vlan": 20,
  "mount": { "source": "/data/app/immich", "target": "/data" }
}
```

Any field you leave out comes from the global config (`/etc/pve-compose/pve-compose.json`) or
gets detected from the host. Full reference in [docs/configuration.md](docs/configuration.md).

## Docs

[Getting started](docs/getting-started.md) ·
[Commands](docs/commands.md) ·
[Configuration](docs/configuration.md) ·
[Templates](docs/templates.md) ·
[Architecture](docs/architecture.md) ·
[Performance](docs/performance.md) ·
[Troubleshooting](docs/troubleshooting.md) ·
[FAQ](docs/faq.md) ·
[Contributing](CONTRIBUTING.md)

## License

[MIT](LICENSE)
