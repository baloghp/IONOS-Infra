# Network and firewall policy

Target firewall and access policy for the 3-VPS CVForge setup.

Step-zero admin access plan: `Plan/04-admin-vpn-step-zero.md`
Server-to-server WireGuard plan: `Plan/06-wireguard-server-network.md`

## Principles

- VPS-2 Frontend is the only public HTTP/HTTPS entry point.
- VPS-1 Backend and VPS-3 Infra do not expose service ports directly to the internet.
- Databases, Valkey, Docker sockets, and Caddy admin APIs are never public.
- Admin interfaces are either VPN/IP-restricted or protected with strong authentication.
- OpenBao requires MFA for human admin access.
- Docker services bind to `127.0.0.1` or private interface addresses unless they must be reached by another server.

## Firewall Layers

Use three layers.

| Layer | Purpose | Required policy |
|---|---|---|
| IONOS firewall / cloud firewall | First network boundary before packets reach the VPS | Allow only required public ports per server |
| Host firewall | Main server-level enforcement | Use `nftables` or Docker-aware `iptables` rules; do not rely on UFW alone with Docker-published ports |
| Docker binding rules | Prevent accidental exposure from Compose files | Publish services to `127.0.0.1` or private IPs; only Caddy publishes public `80`/`443` |

Preferred host firewall: **nftables**.

If using UFW for convenience, also enforce Docker traffic with the `DOCKER-USER` chain, because Docker-published ports can bypass normal UFW input rules.

## Public Port Policy

### VPS-2 Frontend

Only VPS-2 exposes public web traffic.

| Port | Source | Purpose |
|---:|---|---|
| `22/tcp` | Admin VPN / emergency admin source only | SSH |
| `80/tcp` | Public | Caddy HTTP / ACME / redirect |
| `443/tcp` | Public | Caddy HTTPS |

Blocked publicly:

- CVForge container port
- Parsr container port
- AIACC container port
- Caddy admin API `2019`
- Docker daemon/socket

### VPS-1 Backend

No public app/database ports.

| Port/service | Source | Purpose |
|---|---|---|
| `22/tcp` | Admin VPN / emergency admin source only | SSH |
| Supabase API/Studio ports | VPS-2 private IP only | Caddy upstream |
| LiteLLM `4000/tcp` | VPS-2 private IP only | Caddy/CVForge upstream |
| Unleash port | VPS-2 private IP only | Caddy/CVForge upstream |
| Production Postgres | Approved private hosts only | Product DB |
| Infra Postgres | Approved private hosts only | Infra DB |
| Valkey `6379/tcp` | Approved private hosts only | Cache/queue |

### VPS-3 Infra/DevOps

No public HTTP/HTTPS edge.

| Port/service | Source | Purpose |
|---|---|---|
| `22/tcp` | Admin VPN / emergency admin source only | SSH |
| OpenBao | VPS-2 private IP and admin/VPN only | Secrets |
| Forgejo | VPS-2 private IP and admin/VPN only | Git |
| Woodpecker UI/API | VPS-2 private IP and admin/VPN only | CI/CD |
| GlitchTip | VPS-2 private IP and admin/VPN only | Error tracking |
| n8n | VPS-2 private IP and admin/VPN only | Automation |

Woodpecker agents should not expose inbound ports unless explicitly required.

## Recommended Connectivity

Selected server-to-server network:

```text
WireGuard private network between VPS-1, VPS-2, VPS-3
```

Use WireGuard IPs for upstream traffic and firewall rules:

- VPS-2 Caddy -> VPS-1 backend services
- VPS-2 Caddy -> VPS-3 infra services
- VPS-3 automation/CI -> VPS-1/VPS-2 deployment targets
- GlitchTip checks -> approved service health endpoints

Use the address plan from `Plan/06-wireguard-server-network.md`:

| Server | WireGuard IP |
|---|---:|
| VPS-1 Backend | `10.44.0.1` |
| VPS-2 Frontend | `10.44.0.2` |
| VPS-3 Infra | `10.44.0.3` |

## Caddy Rules

Caddy runs on VPS-2.

Required:

- Public `80`/`443` only on VPS-2.
- Caddy admin API bound to `localhost:2019`.
- Admin/tooling domains protected with authentication and/or IP/VPN restrictions.
- Upstreams use private IPs, not public service ports.
- Add security headers for public apps.
- Keep Caddy access logs, but avoid logging secrets, tokens, request bodies, or full AI prompts.

Admin/tooling domains:

- `secrets.ittd.app`
- `git.ittd.app`
- `ci.ittd.app`
- `monitor.ittd.app`
- `automate.ittd.app`
- `studio.ittd.app`
- `flags.ittd.app`

These must not be anonymous public admin panels.

## OpenBao Access And MFA

OpenBao runs on VPS-3 and is exposed through VPS-2 Caddy at `secrets.ittd.app`.

Required controls:

- Human admin access requires MFA.
- Prefer OIDC login through an identity provider with MFA.
- If no identity provider is available, use OpenBao login MFA with TOTP.
- Root token is not used for normal operations.
- Initial root token and recovery/unseal keys are stored offline in KeePass or equivalent, split between trusted admins if possible.
- OpenBao audit logging is enabled before production use.
- OpenBao UI/API is IP/VPN-restricted where possible.
- CI/deployment tokens are scoped to exact secret paths and rotated.

Minimum policy model:

| Actor | Access |
|---|---|
| Human admin | MFA-protected admin access |
| Woodpecker deployment | Read-only access to required deployment paths |
| n8n automation | Read-only access only if a workflow truly needs it |
| App runtime | No direct broad OpenBao access on day one; secrets are injected during deployment |

## Docker Compose Rules

Compose files must follow these rules:

- Public ports are published only for Caddy on VPS-2.
- App services on VPS-2 bind to local/container network behind Caddy.
- Backend services bind to private WireGuard/private-network IPs or localhost.
- Infra tools bind to private WireGuard/private-network IPs or localhost.
- No container publishes database ports to `0.0.0.0`.
- No service mounts `/var/run/docker.sock` unless strictly needed.
- Woodpecker agent Docker access is treated as privileged and isolated.

## Implementation Order

1. Complete `Plan/04-admin-vpn-step-zero.md`.
2. Confirm SSH access and provider console access for all VPS.
3. Install and test WireGuard server-to-server traffic from `Plan/06-wireguard-server-network.md`.
4. Configure IONOS firewall rules.
5. Configure host firewall rules.
6. Configure Docker Compose bind addresses.
7. Deploy Caddy on VPS-2.
8. Deploy OpenBao on VPS-3 with MFA and audit logging.
9. Deploy Backend/Infra services behind private ports.
10. Verify from the public internet that only VPS-2 `80/443` is reachable.
11. Verify from VPS-2 that required private upstreams are reachable.

## Acceptance Tests

From an external network:

- `cvforge.ittd.app` responds over HTTPS.
- `aiacc.ittd.app` responds over HTTPS.
- Admin domains require authentication and/or VPN/IP allowlist.
- VPS-1 service ports are closed.
- VPS-3 service ports are closed.
- Database ports are closed.
- Valkey port is closed.

From VPS-2:

- Caddy can reach required VPS-1 upstreams.
- Caddy can reach required VPS-3 upstreams.

From deployment automation:

- Woodpecker can fetch only required OpenBao secrets.
- Woodpecker can deploy only to intended VPS targets.

