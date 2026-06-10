# Phase 1: Network And Firewall Baseline

Status: **Completed** (2026-05-18)

Goal: establish the private VPS-to-VPS WireGuard network and enforce the public exposure model before deploying services.

Primary references:

- `Plan/03-network-firewall-policy.md`
- `Plan/06-wireguard-server-network.md`
- `Plan/IONOS Servers.md`
- `Plan/05-implementation-phases/00-admin-vpn-and-hardening.md`

## Operating Rules

- **Tailscale** stays your admin SSH path. Do not replace it with WireGuard.
- **WireGuard** is only for inter-VPS service traffic (Caddy upstreams, CI, databases, etc.).
- Configure IONOS cloud firewall before or in parallel with host firewall changes.
- Keep one open `admin@ts-ionos-*` SSH session while applying firewall rules.
- Use Ansible for repeatable WireGuard and host firewall configuration.
- Do not deploy application stacks in this phase; only network and firewall foundations.
- Record WireGuard public keys and any IONOS panel limitations in the completion record at the end.

## Two Networks (Do Not Mix Them Up)

| Network | Purpose | You use it for |
|---|---|---|
| Tailscale | Admin access from Fedora | `ssh ts-ionos-backend`, Remmina, Ansible |
| WireGuard | VPS-to-VPS private traffic | Caddy → backend/infra, CI deploys, DB access between servers |

After Phase 1:

```text
You  --Tailscale-->  ts-ionos-*  --SSH admin-->
VPS-2 Caddy  --WireGuard 10.44.0.1-->  Backend services
VPS-2 Caddy  --WireGuard 10.44.0.3-->  Infra services
```

## Target Result

By the end of this phase:

- WireGuard mesh is up on all three VPS with stable IPs.
- All VPS can ping each other over `10.44.0.x`.
- IONOS firewall allows only required public ports per server.
- Host firewall (`nftables`) enforces the same policy on each VPS.
- VPS-2 is the only server with public `80/tcp` and `443/tcp`.
- VPS-1 and VPS-3 do not expose app, database, or infra ports to the internet.
- UDP `51820` is open only between the three VPS public IPs (not the whole internet).
- Admin SSH over Tailscale still works.
- Public SSH policy is documented for later tightening in Phase 1 or after Caddy is live.

## Address And Server Reference

| Role | SSH alias (admin) | Public IP | WireGuard IP |
|---|---|---:|---:|
| VPS-1 Backend | `ts-ionos-backend` | `82.165.44.144` | `10.44.0.1` |
| VPS-2 Frontend | `ts-ionos-frontend` | `217.154.18.227` | `10.44.0.2` |
| VPS-3 Infra | `ts-ionos-infra` | `82.165.34.239` | `10.44.0.3` |

WireGuard listen port on all VPS: `51820/udp`

## Step 1.1: Confirm Phase 0 Prerequisites

Status: **Completed**

Purpose: ensure admin access and automation still work before changing network boundaries.

From Fedora:

```bash
ssh ts-ionos-backend 'whoami && hostname'
ssh ts-ionos-frontend 'whoami && hostname'
ssh ts-ionos-infra 'whoami && hostname'
```

From `ansible/` (must run inside this directory so `ansible.cfg` and inventory load):

```bash
cd ansible
ansible all -m ping
ansible all -b -m command -a "whoami"
```

If you run `ansible` from the repo root, you will see `provided hosts list is empty` because inventory is not loaded. That is expected; always use `cd ansible` first.

Confirm IONOS console access still works for all three VPS.

Acceptance:

- [X] All three VPS answer over Tailscale SSH as `admin`.
- [X] Ansible `ping` succeeds for all hosts.
- [X] Provider console access is still available.

Completion note: SSH over Tailscale returns `admin` on all three VPS. Ansible `ping` and `ansible all -b -m command -a "whoami"` return `root` when run from `ansible/`.

## Step 1.2: Document Current Public Exposure (Baseline Scan)

Status: **Completed**

Purpose: know what is reachable from the internet before tightening rules.

From your Fedora workstation (not over Tailscale), scan each public IP:

```bash
nmap -Pn -p 22,80,443,51820 82.165.44.144
nmap -Pn -p 22,80,443,51820 217.154.18.227
nmap -Pn -p 22,80,443,51820 82.165.34.239
```

WireGuard uses **UDP** `51820`. The commands above scan TCP only; `51820/tcp filtered` is expected before WireGuard is up. Optional UDP check:

```bash
nmap -Pn -sU -p 51820 82.165.44.144 217.154.18.227 82.165.34.239
```

### Baseline scan results (2026-05-18)

| VPS | Public IP | `22/tcp` | `80/tcp` | `443/tcp` | `51820/tcp` |
|---|---|---|---|---|---|
| Backend | `82.165.44.144` | open | closed | closed | filtered |
| Frontend | `217.154.18.227` | open | open | open | filtered |
| Infra | `82.165.34.239` | open | closed | closed | filtered |

Notes:

- SSH (`22`) is open on all three VPS (expected until public SSH is restricted).
- Frontend already exposes `80` and `443` publicly (likely existing listener or provider default; Caddy will use these in Phase 2).
- Backend and Infra do not expose HTTP/HTTPS on public IPs (good).
- No unexpected database or app ports in this scan.

Optional broader scan:

```bash
nmap -Pn --top-ports 1000 217.154.18.227
```

Acceptance:

- [X] You have a written baseline of open public ports per VPS before changes.
- [X] Unexpected open ports are noted for cleanup.

Completion note: Baseline TCP scan recorded above. Frontend `80`/`443` open is expected target state for the public gateway; investigate what is listening if it is not intentional before Phase 2.

### Frontend broader scan (`--top-ports 1000`, 2026-05-18)

| Port | State | Notes |
|---:|---|---|
| `22/tcp` | open | SSH |
| `80/tcp` | open | HTTP (expected for Caddy) |
| `443/tcp` | open | HTTPS (expected for Caddy) |
| `6000/tcp` | open | **Unexpected** — nmap labels as X11; investigate and close if not required |
| `4000/tcp` | closed | — |
| `5678/tcp` | closed | — |
| `8000/tcp` | closed | — |
| Other top 1000 | filtered | No response |

Investigation result (`ss -tlnp`, 2026-05-18): all three ports are **`docker-proxy`** bound to **`0.0.0.0`** (public):

| Port | Process |
|---:|---|
| `80`, `443`, `2019` | `docker-proxy` → `caddy` |
| `6000` | `docker-proxy` → `parsr` |
| `3001` | `docker-proxy` → `cvforge` |
| `4000` | `docker-proxy` → `litellm` |

Frontend cleanup complete (2026-05-18): no containers, no legacy listeners; `80`/`443`/`6000` closed from internet. Sub-plan: `Plan/05-implementation-phases/01a-frontend-vps-docker-cleanup.md`.

## Step 1.2a: Frontend Docker cleanup (sub-plan)

Status: **Completed** (2026-05-18)

Purpose: remove or document leftover Docker on VPS-2 before IONOS/host firewall rules and Phase 2 Caddy.

Execute: `Plan/05-implementation-phases/01a-frontend-vps-docker-cleanup.md`

Acceptance:

- [X] All public `docker-proxy` ports mapped to containers (see sub-plan inventory).
- [X] Unneeded stacks stopped/removed (`/opt/AIHUB/*` compose down; backup at `/home/admin/frontend-docker-backup-2026-05-18.tgz`).
- [X] Ports `6000`, `3001`, `4000`, `2019` not open; `80`/`443` closed until Phase 2.
- [X] Post-cleanup `nmap` recorded (22 open; 80/443/6000 closed).

## Step 1.3: Configure IONOS Cloud Firewall (Manual)

Status: **Completed** (verified)

Purpose: first network boundary at the provider panel.

Log in to IONOS and open the firewall/security settings for each VPS.

### VPS-2 Frontend (`217.154.18.227`)

Allow inbound:

| Protocol | Port | Source | Purpose |
|---|---:|---|---|
| TCP | `80` | Any (`0.0.0.0/0`) | Caddy HTTP / ACME |
| TCP | `443` | Any | Caddy HTTPS |
| UDP | `51820` | `82.165.44.144`, `82.165.34.239` | WireGuard from Backend and Infra |
| TCP | `22` | Optional: restrict later | SSH (temporary if still public) |

Do not open application container ports publicly.

### VPS-1 Backend (`82.165.44.144`)

Allow inbound:

| Protocol | Port | Source | Purpose |
|---|---:|---|---|
| UDP | `51820` | `217.154.18.227`, `82.165.34.239` | WireGuard from Frontend and Infra |

Block or do not add:

- Public HTTP/HTTPS (`80`, `443`)
- Database ports
- Application service ports

SSH (`22`): keep reachable only if you still rely on public SSH as emergency backup. Prefer Tailscale-only SSH once host firewall is proven.

### VPS-3 Infra (`82.165.34.239`)

Allow inbound:

| Protocol | Port | Source | Purpose |
|---|---:|---|---|
| UDP | `51820` | `82.165.44.144`, `217.154.18.227` | WireGuard from Backend and Frontend |

Block or do not add:

- Public HTTP/HTTPS edge
- Forgejo, Woodpecker, GlitchTip, n8n, OpenBao ports on public interface

Acceptance:

- [X] VPS-2 allows public `80/tcp` and `443/tcp`.
- [X] All three VPS allow UDP `51820` from the other two public IPs (or documented IONOS limitation).
- [X] VPS-1 has no public app/database rules; public SSH `22` not required (admin via Tailscale).
- [X] VPS-3 has no public HTTP/HTTPS edge rules; public SSH `22` not required (admin via Tailscale).

Completion note: record any IONOS UI limitation in the phase completion record at end of file if not already noted.

## Step 1.4: Implement Ansible WireGuard Role

Status: **Completed** (2026-05-18 — playbook applied, mesh verified)

Purpose: automate WireGuard install, keys, config, and service on all VPS.

Target playbook (two plays: keys on all hosts, then mesh config with `serial: 1`):

```bash
cd ansible
ansible-playbook playbooks/wireguard.yml
```

Role layout: `ansible/roles/wireguard/` (`keys.yml`, `config.yml`, `templates/wg0.conf.j2`). Mesh variables in `inventory/group_vars/all.yml`.

The `wireguard` role should manage on each host:

- Install `wireguard` package.
- Generate per-host private/public keys (store private key only on that host).
- Deploy `/etc/wireguard/wg0.conf` from templates using inventory variables.
- Enable and start `wg-quick@wg0`.
- Set `net.ipv4.ip_forward` if needed later (not required for basic mesh ping).

### Per-host WireGuard config summary

**VPS-1 Backend** (`10.44.0.1/24`):

- Peers: Frontend `10.44.0.2` @ `217.154.18.227:51820`, Infra `10.44.0.3` @ `82.165.34.239:51820`

**VPS-2 Frontend** (`10.44.0.2/24`):

- Peers: Backend `10.44.0.1` @ `82.165.44.144:51820`, Infra `10.44.0.3` @ `82.165.34.239:51820`

**VPS-3 Infra** (`10.44.0.3/24`):

- Peers: Backend `10.44.0.1` @ `82.165.44.144:51820`, Frontend `10.44.0.2` @ `217.154.18.227:51820`

Use `PersistentKeepalive = 25` on all peers.

Full config examples: `Plan/06-wireguard-server-network.md`

### Suggested Ansible variables (`inventory/group_vars/all.yml` or host_vars)

```yaml
wireguard_port: 51820
wireguard_network: 10.44.0.0/24

wireguard_backend_wg_ip: 10.44.0.1
wireguard_frontend_wg_ip: 10.44.0.2
wireguard_infra_wg_ip: 10.44.0.3

wireguard_backend_public_ip: 82.165.44.144
wireguard_frontend_public_ip: 217.154.18.227
wireguard_infra_public_ip: 82.165.34.239
```

Public keys can be generated on first run and stored in host_vars (public keys only, never private keys in Git).

Acceptance:

- [X] `wireguard` role is implemented (not placeholder).
- [X] Playbook runs without error on all three VPS.
- [X] `wg0` interface exists on each VPS.

## Step 1.5: Verify WireGuard Mesh Connectivity

Status: **Completed** (2026-05-18)

Purpose: confirm encrypted VPS-to-VPS path works before firewall lockdown.

On each VPS (via Tailscale SSH):

```bash
sudo wg show
ip -brief addr show wg0
```

From VPS-1:

```bash
ping -c 3 10.44.0.2
ping -c 3 10.44.0.3
```

From VPS-2:

```bash
ping -c 3 10.44.0.1
ping -c 3 10.44.0.3
```

From VPS-3:

```bash
ping -c 3 10.44.0.1
ping -c 3 10.44.0.2
```

Or from Fedora with Ansible:

```bash
ansible ts-ionos-backend -b -m command -a "ping -c 3 10.44.0.2"
ansible ts-ionos-backend -b -m command -a "ping -c 3 10.44.0.3"
ansible ts-ionos-frontend -b -m command -a "ping -c 3 10.44.0.1"
ansible ts-ionos-frontend -b -m command -a "ping -c 3 10.44.0.3"
ansible ts-ionos-infra -b -m command -a "ping -c 3 10.44.0.1"
ansible ts-ionos-infra -b -m command -a "ping -c 3 10.44.0.2"
```

Check `wg show` for recent handshakes on each peer.

Acceptance:

- [X] `wg show` reports recent handshakes between all peers.
- [X] Each VPS can ping the other two WireGuard IPs.
- [X] Tailscale SSH still works after WireGuard is enabled.

## Step 1.6: Implement Ansible Host Firewall Role

Status: **Completed** (2026-05-18 — role + `playbooks/firewall.yml` applied on all VPS)

Purpose: enforce server-level rules with `nftables` (Docker-aware).

Preferred tool: **nftables** with explicit rules for Tailscale admin, WireGuard mesh, and public web on VPS-2 only.

The `firewall` role should manage:

- Install `nftables`.
- Enable `nftables` service.
- Deploy ruleset per host group (`backend`, `frontend`, `infra`).
- Allow established/related traffic.
- Allow loopback.
- Allow Tailscale interface traffic for SSH (admin path).
- Allow WireGuard `wg0` traffic within `10.44.0.0/24`.
- Allow VPS-2 public `80/tcp` and `443/tcp` on public interface.
- Default deny inbound on public interface for everything else.
- Optional: restrict SSH on public interface to Tailscale only (policy decision).

Connect the role via a dedicated playbook or extend hardening:

```bash
cd ansible
ansible-playbook playbooks/firewall.yml
```

If `playbooks/firewall.yml` does not exist yet, create it targeting `ionos` with the `firewall` role.

### VPS-1 Backend firewall intent

Allow inbound:

- SSH from Tailscale (and optionally localhost).
- WireGuard mesh (`10.44.0.0/24` on `wg0`).
- Backend service ports from `10.44.0.2` only (when services exist).
- Deployment ports from `10.44.0.3` only where required.
- Database and Valkey only from approved WireGuard IPs.

Deny inbound on public interface:

- All application and database ports.

### VPS-2 Frontend firewall intent

Allow inbound:

- SSH from Tailscale.
- WireGuard mesh on `wg0`.
- Public `80/tcp` and `443/tcp`.
- UDP `51820` from Backend and Infra public IPs on public interface (if not fully handled by IONOS firewall).

Deny inbound on public interface:

- CVForge, Parsr, AIACC container ports.
- Caddy admin API port `2019` from internet.

### VPS-3 Infra firewall intent

Allow inbound:

- SSH from Tailscale.
- WireGuard mesh on `wg0`.
- Infra tool ports from `10.44.0.2` only (when services exist).

Deny inbound on public interface:

- HTTP/HTTPS edge, Forgejo, Woodpecker, GlitchTip, n8n, OpenBao.

### Docker note

Docker-published ports can bypass UFW. Use `nftables` and plan for `DOCKER-USER` chain rules when Docker is deployed in Phase 2+. For Phase 1, ensure no application containers are publishing public ports yet.

Acceptance:

- [X] `firewall` role is implemented (not placeholder).
- [X] `nftables` is active on all three VPS.
- [X] Rules differ appropriately per server role (`backend`, `frontend`, `infra` group_vars).

Role paths: `ansible/roles/firewall/`, profiles in `inventory/group_vars/{backend,frontend,infra}.yml`.

## Step 1.7: Apply Host Firewall And Verify Admin Access

Status: **Completed** (2026-05-18)

Purpose: confirm firewall rules do not break Tailscale SSH.

Keep one open SSH session. Apply firewall playbook. Test new sessions:

```bash
ssh ts-ionos-backend 'whoami'
ssh ts-ionos-frontend 'whoami'
ssh ts-ionos-infra 'whoami'
```

If locked out:

1. Use existing SSH session, or
2. Use IONOS console, or
3. Temporarily relax nftables rule and fix.

Acceptance:

- [X] New Tailscale SSH sessions work after firewall apply (`ansible ionos -m ping` OK).
- [X] WireGuard ping still works between all VPS.

## Step 1.8: External Port Verification

Status: **Completed** (2026-05-18)

Purpose: prove only intended ports are reachable from the internet.

From Fedora (public internet path, not Tailscale):

```bash
nmap -Pn -p 22,80,443,51820,5432,6379,4000 82.165.44.144
nmap -Pn -p 22,80,443,51820,5432,6379,4000 217.154.18.227
nmap -Pn -p 22,80,443,51820,5432,6379,4000 82.165.34.239
```

Expected after Phase 1 (services not deployed yet):

| VPS | Expected open from internet |
|---|---|
| VPS-1 Backend | Ideally nothing, or only `22` if public SSH not yet restricted; `51820/udp` only if IONOS cannot source-restrict |
| VPS-2 Frontend | `80`, `443`; optionally `22` until restricted |
| VPS-3 Infra | Ideally nothing except possibly `22` / `51820` per provider rules |

Must be closed from internet on all VPS:

- `5432` (Postgres)
- `6379` (Valkey)
- `4000` (LiteLLM)
- Application container ports

Post-change scan (2026-05-18):

| VPS | 22 | 80/443 | 5432/6379/4000 |
|-----|-----|--------|------------------|
| Backend | filtered | filtered | filtered |
| Frontend | open (temporary policy) | closed (no listener until Caddy) | filtered |
| Infra | filtered | filtered | filtered |

Note: `nmap` tests TCP; WireGuard uses UDP `51820` (allowed at IONOS + host).

Acceptance:

- [X] VPS-2 public `80`/`443` not blocked by host firewall (closed until Caddy in Phase 2).
- [X] VPS-1 database and app ports are not reachable from internet.
- [X] VPS-3 infra tool ports are not reachable from internet.

## Step 1.9: Verify WireGuard Path For Future Upstreams

Status: **Completed** (2026-05-18)

Purpose: confirm VPS-2 can reach private IPs on Backend and Infra (foundation for Caddy in Phase 2).

From VPS-2:

```bash
ping -c 3 10.44.0.1
ping -c 3 10.44.0.3
```

Or from Fedora:

```bash
cd ansible
ansible ts-ionos-frontend -b -m shell -a "ping -c 3 10.44.0.1 && ping -c 3 10.44.0.3"
```

### Results (2026-05-18)

| Target | Test | Result |
|--------|------|--------|
| `10.44.0.1` (Backend) | ping ×3 | 0% loss, ~0.7 ms RTT |
| `10.44.0.3` (Infra) | ping ×3 | 0% loss, ~0.7 ms RTT |
| `10.44.0.1:4000` | TCP (LiteLLM, not deployed) | closed/filtered (expected) |
| `10.44.0.1:5432` | TCP (Postgres, not deployed) | closed/filtered (expected) |
| `10.44.0.3:8200` | TCP (OpenBao, not deployed) | closed/filtered (expected) |
| `10.44.0.3:3000` | TCP (Forgejo, not deployed) | closed/filtered (expected) |

WireGuard peers on Frontend show endpoints at Backend and Infra public IPs with active mesh.

### Caddy upstream rule (Phase 2+)

**Always use WireGuard IPs in Caddy `reverse_proxy`, never the VPS public IPs.**

| Upstream role | Address | Example hostnames (Phase 2+) |
|---------------|---------|------------------------------|
| Backend services | `10.44.0.1` | `proxy.ittd.app`, `flags.ittd.app`, Supabase studio/API |
| Infra services | `10.44.0.3` | `secrets.ittd.app`, `git.ittd.app`, `ci.ittd.app`, `monitor.ittd.app`, `automate.ittd.app` |

Public IPs (`82.165.44.144`, `82.165.34.239`) are not reachable for app traffic by design (IONOS + host firewall). Full port-level upstream tests belong in Phase 2/5/6 when services listen on `wg0`.

Acceptance:

- [X] VPS-2 can reach `10.44.0.1` and `10.44.0.3` over WireGuard.
- [X] Documented that Caddy must use WireGuard IPs, not public IPs, for upstreams.

## Step 1.10: SSH Exposure Policy Decision

Status: **Completed** (2026-05-18)

Purpose: document whether public SSH stays open temporarily or is restricted now.

### Decision

| VPS | Public SSH (`22/tcp`) | Admin access |
|-----|------------------------|--------------|
| **VPS-1 Backend** | **Closed** (IONOS + nftables) | Tailscale only: `ssh ts-ionos-backend` |
| **VPS-2 Frontend** | **Open** (intentional) | Tailscale preferred; public `admin@217.154.18.227` OK as backup |
| **VPS-3 Infra** | **Closed** (IONOS + nftables) | Tailscale only: `ssh ts-ionos-infra` |

Frontend keeps public SSH for convenience during gateway rollout. Backend and Infra stay Tailscale-only.

### Access paths (team reference)

| Path | Use for |
|------|---------|
| **Normal admin** | `admin@ts-ionos-*` over Tailscale (MagicDNS aliases) |
| **Frontend backup** | `ssh admin@217.154.18.227` or `ionos-frontend` if configured |
| **Emergency** | IONOS provider console (all VPS) |

Implementation: `firewall_allow_public_ssh: true` in `inventory/group_vars/frontend.yml`; `false` on backend/infra groups.

fail2ban continues to ignore Fedora Tailscale IP `100.118.29.96` in `inventory/group_vars/all.yml`.

To close Frontend public SSH later: set `firewall_allow_public_ssh: false` and re-run `ansible-playbook playbooks/firewall.yml` (Tailscale SSH must work first).

Acceptance:

- [X] SSH exposure policy is documented.
- [X] Team knows normal vs emergency access paths.

## Step 1.11: Final Phase Validation

Status: **Completed** (2026-05-18)

Run all checks before moving to Phase 2.

WireGuard:

```bash
ansible ionos -b -m command -a "wg show"
```

Connectivity (sample):

```bash
ansible ts-ionos-frontend -b -m command -a "ping -c 2 10.44.0.1"
ansible ts-ionos-frontend -b -m command -a "ping -c 2 10.44.0.3"
```

Admin access:

```bash
ssh ts-ionos-backend 'hostname && whoami'
ssh ts-ionos-frontend 'hostname && whoami'
ssh ts-ionos-infra 'hostname && whoami'
```

Firewall:

```bash
ansible all -b -m command -a "systemctl is-active nftables"
```

### Validation results (2026-05-18)

| Check | Result |
|-------|--------|
| `wg show` all hosts | Active handshakes on all peer pairs |
| Frontend → `10.44.0.1` / `10.44.0.3` | 0% ping loss |
| Tailscale admin (`ansible ionos`) | `admin@ubuntu` on all three |
| `nftables` | `active` on Backend, Frontend, Infra |
| External nmap | Backend/Infra: 22 filtered, no app/db ports; Frontend: 22 open, 80/443 closed (no listener yet) |

Acceptance:

- [X] WireGuard mesh works on all three VPS.
- [X] Tailscale admin SSH works on all three VPS.
- [X] Host firewall is active on all three VPS.
- [X] Only VPS-2 is intended to expose public web ports.
- [X] Backend and Infra are not publicly exposing app/database ports.
- [X] Ready for Phase 2: Caddy, TLS, DNS on VPS-2.

## Phase 1 Completion Record

```text
WireGuard port: 51820
Host firewall tool: nftables
IONOS firewall source-restricted UDP 51820: yes (peer public IPs only, per Step 1.3)
Public SSH policy after Phase 1: Backend/Infra closed (Tailscale only); Frontend open (intentional).

Backend WireGuard public key:  GdINr294NKubRKdZ8ZtQx2hXcAylG+753+p1qGXmmV4=
Frontend WireGuard public key: vTt7l3Eq6/xQTlOnPR9kwoh0BvHBc1XMK9r28cbFQEQ=
Infra WireGuard public key:    lvxXmElV5UCdUXI8oSWgb9xgDNS/lX12qeoCbGhpvHM=

Baseline scan notes (ports open before changes):
  Backend  82.165.44.144:  22 open; 80/443 closed
  Frontend 217.154.18.227: 22, 80, 443, 6000 open (legacy Docker); 3001/4000/2019 via docker-proxy
  Infra    82.165.34.239:  22 open; 80/443 closed

Post-change scan notes (ports open after changes, 2026-05-18):
  Backend  82.165.44.144:  22 filtered; 80/443/4000/5432/6379 filtered
  Frontend 217.154.18.227: 22 open; 80/443 closed (ready for Caddy); app/db ports filtered
  Infra    82.165.34.239:  22 filtered; 80/443/4000/5432/6379 filtered

Date completed: 2026-05-18
```

## What Comes Next

Phase 2: Frontend gateway, TLS, and static site on VPS-2.

- Install Docker on VPS-2.
- Deploy Caddy with public `80`/`443`.
- Point `ittd.app` DNS to `217.154.18.227`.
- Configure Caddy upstreams to `10.44.0.1` and `10.44.0.3` over WireGuard.

Execution guide: `Plan/05-implementation-phases/02-frontend-gateway-tls-static-site.md`
