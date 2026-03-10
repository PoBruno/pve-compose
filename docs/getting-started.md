# Getting Started

Step-by-step guide to get pve-compose running on your Proxmox host.

## Prerequisites

- **Proxmox VE 7.x or 8.x** (tested on 8.4)
- **Root access** to the Proxmox host
- **jq** installed (`apt install jq`)
- At least one storage pool (ZFS, LVM-Thin, or directory-based)
- A directory for your services (e.g., `/data/app/`)

## 1. Install pve-compose

**From .deb package**:

```bash
dpkg -i pve-compose_0.1.0-1_all.deb
```

**From source**:

```bash
git clone https://github.com/PoBruno/pve-compose.git
cd pve-compose
make install
```

Verify:

```bash
pve-compose --version
# pve-compose 0.1.0
```

## 2. Run setup

```bash
pve-compose setup
```

This auto-detects your Proxmox environment and creates `/etc/pve-compose/pve-compose.json` with defaults for storage, network, DNS, and bridge.

If you prefer non-interactive mode:

```bash
pve-compose setup --non-interactive
```

## 3. Create a Docker template (recommended)

```bash
pve-compose template create
```

This creates an LXC container, installs Docker inside it, and converts it to a template. Takes about 2 minutes once. After this, every `pve-compose up` clones the template in ~10 seconds instead of installing Docker from scratch.

Check your templates:

```bash
pve-compose template list
```

**This step is optional.** Without a template, `pve-compose up` downloads a vanilla Debian image and installs Docker automatically - it just takes longer the first time.

## 4. Deploy your first service

```bash
mkdir -p /data/app/speedtest && cd /data/app/speedtest

cat > docker-compose.yml <<'EOF'
services:
  speedtest:
    image: lscr.io/linuxserver/speedtest-tracker:latest
    ports:
      - "8080:80"
    volumes:
      - ./config:/config
    environment:
      - TZ=America/Sao_Paulo
EOF

pve-compose up -d
```

What happens behind the scenes:

1. No `lxc.json` found -> auto-generates one with detected defaults
2. Creates LXC container (clones from template if available)
3. Configures bind mount: `$PWD -> /data` inside the container
4. Starts the container
5. Ensures Docker is installed and running
6. Runs `docker compose up -d` inside the container

## 5. Verify everything

```bash
# Check container and compose status
pve-compose status

# Run 10 diagnostic checks
pve-compose doctor

# Follow logs
pve-compose logs -f

# List running containers
pve-compose ps
```

## 6. Customize (optional)

If you want to adjust resources before creating the container:

```bash
mkdir -p /data/app/immich && cd /data/app/immich
# add your docker-compose.yml

pve-compose plan          # generates lxc.json with detected values

nano lxc.json             # adjust memory, IP, cores, etc.

pve-compose up -d         # creates container with your config
```

After the container exists, you can still change some settings:

```bash
# Edit lxc.json (change memory, cores, tags...)
nano lxc.json

# Apply changes (hot-apply when possible, prompts for restart if needed)
pve-compose apply
```

## 7. Global overview

See Docker containers running across all your LXCs:

```bash
pve-compose overview
```

Output:

```
┌─ CT 100 - speedtest (192.168.1.54) ──────────────────────────────────┐
│ NAMES       IMAGE                                   STATUS   PORTS   │
│ speedtest   lscr.io/linuxserver/speedtest-tracker   Up 2h    80/tcp  │
└──────────────────────────────────────────────────────────────────────┘

┌─ CT 200 - immich (192.168.1.200) ────────────────────────────────────┐
│ NAMES           IMAGE                              STATUS   PORTS    │
│ immich_server   ghcr.io/immich-app/immich-server   Up 3h    2283/tcp │
│ immich_redis    redis:6.2-alpine                   Up 3h    6379/tcp │
└──────────────────────────────────────────────────────────────────────┘
```

## Next Steps

- [Commands Reference](commands.md) - full list of all commands
- [Configuration](configuration.md) - `lxc.json` and global config details
- [Templates](templates.md) - template management
- [Troubleshooting](troubleshooting.md) - common issues and fixes
- [FAQ](faq.md) - design decisions and alternatives
