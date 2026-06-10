# Sub-plan: VPS-2 Frontend Docker cleanup

Goal: inventory and remove leftover Docker workloads on Frontend before firewall hardening and Phase 2 Caddy deployment.

Parent phase: `Plan/05-implementation-phases/01-network-and-firewall-baseline.md` → Step 1.2a

Server: **VPS-2 Frontend** — `ts-ionos-frontend` / `217.154.18.227`

## Why this matters

Baseline scans and `ss` showed **old single-VPS Docker stacks** binding publicly on `0.0.0.0`:

| Port | Listener | Container (confirmed) |
|---:|---|---|
| `80/tcp` | `docker-proxy` | `caddy` |
| `443/tcp` | `docker-proxy` | `caddy` |
| `2019/tcp` | `docker-proxy` | `caddy` (admin API — must not be public) |
| `6000/tcp` | `docker-proxy` | `parsr` |
| `3001/tcp` | `docker-proxy` | `cvforge` (public — should be behind Caddy only) |
| `4000/tcp` | `docker-proxy` | `litellm` (belongs on VPS-1 Backend) |

This is **not** the target 3-VPS layout. The host must be cleaned before IONOS/host firewall rules and before Phase 2 installs a new Caddy gateway.

## Operating rules

- Do this **before** Phase 1 Step 1.3 (IONOS firewall) and **before** Phase 2 Caddy install.
- Keep Tailscale SSH access; do not lock yourself out.
- **Do not** run `docker system prune -a --volumes` until you know what to keep.
- Backup compose directories and `.env` files before removal.
- Prefer `docker compose down` in project directories when compose files exist.
- **Do not remove volumes** until Backend/Infra Postgres are ready and you confirm data migration needs.
- After cleanup, re-run `ss` and `nmap` to confirm only expected ports remain.

## Inventory snapshot (2026-05-18)

Captured with:

```bash
sudo docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

```text
NAMES              IMAGE                                 STATUS                     PORTS
caddy              caddy:2                               Up 5 days (unhealthy)      0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:2019->2019/tcp, 443/udp
n8n                n8nio/n8n:latest                      Exited (0) 7 weeks ago
postgresql-n8n     postgres:16                           Exited (0) 7 weeks ago
parsr              axarev/parsr:latest                   Up 7 weeks                 0.0.0.0:6000->3001/tcp
cvforge            baloghp/cvforge:latest                Up 7 weeks (unhealthy)     0.0.0.0:3001->3001/tcp
litellm            ghcr.io/berriai/litellm:main-latest   Up 7 weeks                 0.0.0.0:4000->4000/tcp
litellm-db         postgres:16-alpine                    Exited (0) 7 weeks ago
watchtower         containrrr/watchtower:latest          Up 7 weeks (healthy)
unruffled_galois   axarev/parsr                          Exited (255) 7 weeks ago
aiacc              baloghp/ai-act-compliance:latest      Exited (0) 7 weeks ago
litellm-postgres   postgres:15-alpine                    Exited (0) 9 months ago
```

Conclusion: Frontend still runs the **legacy all-in-one stack**. Services that belong on Backend or Infra must be removed from this host.

## Compose layout on disk (`/opt/AIHUB/`)

Discovered on VPS (2026-05-18):

```bash
sudo docker inspect caddy cvforge parsr litellm n8n --format '{{.Name}} -> {{index .Config.Labels "com.docker.compose.project.working_dir"}}'
sudo find /opt /srv /root /home/admin -name 'docker-compose.yml' -o -name 'compose.yml' 2>/dev/null
```

**Container → compose project:**

| Container(s) | Compose working dir |
|---|---|
| `caddy` | `/opt/AIHUB/Infra` |
| `cvforge`, `parsr` | `/opt/AIHUB/CVForge` |
| `litellm`, `litellm-db` | `/opt/AIHUB/LiteLLM` |
| `n8n`, `postgresql-n8n` | `/opt/AIHUB/Automation` |
| `aiacc` (exited) | `/opt/AIHUB/AIACC` (compose file present; confirm with inspect if needed) |

**All `docker-compose.yml` under `/opt/AIHUB/`:**

| Path | Likely role |
|---|---|
| `/opt/AIHUB/Infra/docker-compose.yml` | Caddy (+ possibly Watchtower) |
| `/opt/AIHUB/CVForge/docker-compose.yml` | CVForge + Parsr |
| `/opt/AIHUB/LiteLLM/docker-compose.yml` | LiteLLM + DB |
| `/opt/AIHUB/Automation/docker-compose.yml` | n8n + Postgres |
| `/opt/AIHUB/AIACC/docker-compose.yml` | AI Act Compliance |
| `/opt/AIHUB/Prod/docker-compose.yml` | Production stack (verify if used) |
| `/opt/AIHUB/Dev/docker-compose.yml` | Dev stack (verify if used) |

## Port and placement map

| Public bind | Container | Image | Target VPS | Action |
|-------------|-----------|--------|------------|--------|
| `80`, `443`, `2019` | `caddy` | caddy:2 | VPS-2 (new gateway) | Stop; backup Caddyfile; redeploy in Phase 2 (no public `2019`) |
| `6000` | `parsr` | axarev/parsr | VPS-2 | Stop; redeploy **private** in Phase 7 |
| `3001` | `cvforge` | baloghp/cvforge | VPS-2 | Stop; redeploy behind Caddy in Phase 7 |
| `4000` | `litellm` | litellm | **VPS-1 Backend** | Stop; deploy on Backend in Phase 5 |
| — | `litellm-db` | postgres:16-alpine | **VPS-1 Backend** | Stop with LiteLLM stack |
| — | `n8n`, `postgresql-n8n` | n8n stack | **VPS-3 Infra** | Stop; deploy on Infra in Phase 6 |
| — | `watchtower` | watchtower | — | **Remove** (not used in target architecture) |
| — | `unruffled_galois` | axarev/parsr (stale) | — | **Remove** |
| — | `aiacc` | ai-act-compliance | VPS-2 | Stop; redeploy in Phase 7 |
| — | `litellm-postgres` | postgres:15-alpine (stale) | — | **Remove** after confirming unused |

## What to redeploy later (reference)

| Service | Correct VPS | Phase |
|---------|-------------|--------|
| Caddy (new) | Frontend | 2 |
| CVForge, Parsr, AIACC | Frontend | 7 |
| LiteLLM (+ Production Postgres) | Backend | 5 |
| n8n (+ Infra Postgres) | Infra | 6 |

## Step A.1: Connect and snapshot current state

Status: **Completed**

```bash
ssh ts-ionos-frontend
```

On the VPS:

```bash
sudo docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
sudo docker compose ls
sudo docker network ls
sudo docker volume ls
sudo ss -tlnp | grep docker-proxy
```

Acceptance:

- [X] Full container list captured (see inventory above).
- [X] Compose projects identified (see `/opt/AIHUB/` layout above).

## Step A.2: Map ports to containers

Status: **Completed**

| Port | Container | Image | Compose path | Action |
|---:|---|---|---|---|
| `80`, `443`, `2019` | `caddy` | caddy:2 | `/opt/AIHUB/Infra` | Stop; backup Caddyfile |
| `6000` | `parsr` | axarev/parsr | `/opt/AIHUB/CVForge` | Stop |
| `3001` | `cvforge` | baloghp/cvforge | `/opt/AIHUB/CVForge` | Stop |
| `4000` | `litellm` | litellm | `/opt/AIHUB/LiteLLM` | Stop |
| — | `litellm-db` | postgres:16-alpine | `/opt/AIHUB/LiteLLM` | Stop with stack |
| — | `n8n`, `postgresql-n8n` | n8n / postgres:16 | `/opt/AIHUB/Automation` | Stop |
| — | `watchtower` | watchtower | `/opt/AIHUB/Infra` (likely) | Stop + remove |
| — | `unruffled_galois` | axarev/parsr | — (orphan) | Remove |
| — | `aiacc` | ai-act-compliance | `/opt/AIHUB/AIACC` | Stop |
| — | `litellm-postgres` | postgres:15-alpine | — (stale orphan) | Remove if unused |

Acceptance:

- [X] Every public `docker-proxy` port is mapped to a container.
- [X] Decision made for each: stop or remove (see action column).
- [X] Compose path filled in for each stack.

## Step A.3: Find compose and config files on disk

Status: **Completed** (2026-05-18)

```bash
sudo find /opt /srv /root /home/admin -name 'docker-compose.yml' -o -name 'compose.yml' 2>/dev/null
ls -la /opt/AIHUB
```

Backup before stopping:

```bash
sudo tar -czf ~/frontend-docker-backup-$(date +%F).tgz \
  /opt/AIHUB/Infra /opt/AIHUB/CVForge /opt/AIHUB/LiteLLM \
  /opt/AIHUB/Automation /opt/AIHUB/AIACC
```

Optional: include `Prod` and `Dev` if they contain env or config you need:

```bash
# add to tar if non-empty / in use:
# /opt/AIHUB/Prod /opt/AIHUB/Dev
```

Check repo reference: `Old_Config/` in this project for original layout hints.

Acceptance:

- [X] Compose files and project directories documented.
- [X] Backup archive created: `/home/admin/frontend-docker-backup-2026-05-18.tgz` (tar leading-`/` warnings are normal).

## Step A.4: Stop and remove legacy stacks

Status: **Completed** (2026-05-18)

Executed on VPS — all stacks removed:

| Project | Containers removed |
|---|---|
| `/opt/AIHUB/Infra` | `caddy`, `watchtower` |
| `/opt/AIHUB/CVForge` | `parsr`, `cvforge` |
| `/opt/AIHUB/LiteLLM` | `litellm`, `litellm-db` |
| `/opt/AIHUB/Automation` | `n8n`, `postgresql-n8n` |
| `/opt/AIHUB/AIACC` | `aiacc` |
| orphans | `unruffled_galois`, `litellm-postgres` |

Recommended approach: **full Frontend Docker reset** for the old layout — stop all legacy containers, keep volumes until migration is planned.

### Option A — Per compose project (preferred)

Run from Frontend in this order (stops public listeners first):

```bash
cd /opt/AIHUB/Infra && sudo docker compose down
cd /opt/AIHUB/CVForge && sudo docker compose down
cd /opt/AIHUB/LiteLLM && sudo docker compose down
cd /opt/AIHUB/Automation && sudo docker compose down
cd /opt/AIHUB/AIACC && sudo docker compose down
```

If `Prod` or `Dev` have running containers (`docker compose ls`), stop those too:

```bash
cd /opt/AIHUB/Prod && sudo docker compose down 2>/dev/null || true
cd /opt/AIHUB/Dev && sudo docker compose down 2>/dev/null || true
```

Remove orphans not managed by compose:

```bash
sudo docker rm -f unruffled_galois litellm-postgres 2>/dev/null || true
```

### Option B — Stop all legacy containers (if compose paths unclear)

```bash
sudo docker stop caddy n8n postgresql-n8n parsr cvforge litellm litellm-db watchtower aiacc 2>/dev/null
sudo docker rm unruffled_galois litellm-postgres 2>/dev/null
```

### After stop — review orphans only

```bash
sudo docker ps -a
# Review before pruning:
# sudo docker network prune
# sudo docker volume prune   # only if sure no data needed
```

**Do not remove** `litellm-db` or `postgresql-n8n` volumes until you confirm whether data must be migrated to Backend/Infra Postgres.

Acceptance:

- [X] All legacy containers stopped or removed.
- [X] `watchtower` and `unruffled_galois` removed.
- [X] No `docker-proxy` on `0.0.0.0` for `6000`, `3001`, `4000`, `2019` (verified via nmap).

## Step A.5: Verify cleanup

Status: **Completed** (2026-05-18)

From the VPS:

```bash
sudo docker ps -a
sudo ss -tlnp | grep -E ':6000|:80|:443|:3001|:4000|:2019' || echo 'no legacy listeners'
```

From Fedora:

```bash
nmap -Pn -p 22,80,443,3001,4000,6000,2019 217.154.18.227
```

Expected after cleanup (before Phase 2 Caddy):

| Port | Expected |
|---:|---|
| `22` | open (SSH, until restricted) |
| `80` | closed |
| `443` | closed |
| `2019` | closed |
| `3001` | closed |
| `4000` | closed |
| `6000` | closed |

Post-cleanup `nmap` from Fedora (2026-05-18):

```text
PORT     STATE
22/tcp   open
80/tcp   closed
443/tcp  closed
2019/tcp filtered
3001/tcp filtered
4000/tcp filtered
6000/tcp closed
```

Acceptance:

- [X] `6000`, `3001`, `4000`, `2019` are not open from the internet.
- [X] `80`/`443` are closed until Phase 2 Caddy is deployed.
- [X] No legacy `docker-proxy` listeners (confirm on VPS with `ss` if desired).

## Step A.6: Document outcome and resume Phase 1

Status: **Completed** — continue Phase 1 at Step 1.3

Update this completion record, then continue:

- `Plan/05-implementation-phases/01-network-and-firewall-baseline.md` → Step 1.3 (IONOS firewall)

Mark Step 1.2a **Completed** in the parent phase file when A.5 acceptance is done.

## Completion record

```text
Date: 2026-05-18
Compose paths (confirmed):
  caddy:     /opt/AIHUB/Infra
  cvforge:   /opt/AIHUB/CVForge
  parsr:     /opt/AIHUB/CVForge
  litellm:   /opt/AIHUB/LiteLLM
  n8n:       /opt/AIHUB/Automation
  aiacc:     /opt/AIHUB/AIACC
  also:      /opt/AIHUB/Prod, /opt/AIHUB/Dev (compose present; not stopped — verify if empty)
Backup archive path: /home/admin/frontend-docker-backup-2026-05-18.tgz

Containers stopped/removed:
  caddy, watchtower, parsr, cvforge, litellm, litellm-db,
  n8n, postgresql-n8n, aiacc, unruffled_galois, litellm-postgres

Post-cleanup nmap: 22 open; 80/443/6000 closed; 2019/3001/4000 filtered
VPS verify: docker ps -a empty; no legacy listeners on ss
Ready to continue Phase 1 Step 1.3: yes
```

## What not to do yet

- Do not install new Caddy stack until this cleanup is verified (Phase 2).
- Do not redeploy LiteLLM or n8n on Frontend — they move to Backend/Infra.
- Do not use Watchtower (pinned updates via Ansible instead).
- Do not open additional public ports for experiments.
