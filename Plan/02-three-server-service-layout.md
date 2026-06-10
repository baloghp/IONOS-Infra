# CVForge three-server architecture

Target architecture for the IONOS 3-VPS setup.

## Overview

| Server | SSH alias | IP | Role |
|---|---|---:|---|
| VPS-1 Backend | `ionos-backend` | `82.165.44.144` | Backend services and data services |
| VPS-2 Frontend | `ionos-frontend` | `217.154.18.227` | Public Caddy/TLS gateway and production apps |
| VPS-3 Infra/DevOps | `ionos-infra` | `82.165.34.239` | Company platform, secrets, CI/CD, monitoring, automation |

Diagram: `Plan/02-three-server-service-layout.mmd`

Network/firewall policy: `Plan/03-network-firewall-policy.md`
Server-to-server WireGuard: `Plan/06-wireguard-server-network.md`

## Public Routing

VPS-2 Frontend is the only public HTTP/HTTPS entry point.

```text
Internet -> DNS -> VPS-2 Caddy -> local apps / VPS-1 backend / VPS-3 infra
```

Caddy on VPS-2 handles:

- TLS termination for `ITTD.app` public domains.
- Routing to local production apps on VPS-2.
- Reverse proxying to Backend services on VPS-1.
- Reverse proxying to Infra tools on VPS-3.

VPS-1 and VPS-3 must not expose app/tool ports directly to the public internet.

## DNS

All public records point to VPS-2 Frontend: `217.154.18.227`.

| Hostname | Target | Upstream |
|---|---:|---|
| `ittd.app` / `@` | `217.154.18.227` | Redirect to `www.ittd.app` |
| `www.ittd.app` | `217.154.18.227` | Static site on VPS-2 |
| `cvforge.ittd.app` | `217.154.18.227` | CVForge on VPS-2 |
| `aiacc.ittd.app` | `217.154.18.227` | AIACC on VPS-2 |
| `parsr.ittd.app` | `217.154.18.227` | Parsr on VPS-2, only if public |
| `supabase.ittd.app` | `217.154.18.227` | Supabase API on VPS-1 |
| `studio.ittd.app` | `217.154.18.227` | Supabase Studio on VPS-1, admin-only |
| `proxy.ittd.app` | `217.154.18.227` | LiteLLM on VPS-1 |
| `flags.ittd.app` | `217.154.18.227` | Unleash on VPS-1, admin-only |
| `secrets.ittd.app` | `217.154.18.227` | OpenBao on VPS-3, admin/deployment-only |
| `git.ittd.app` | `217.154.18.227` | Forgejo on VPS-3 |
| `ci.ittd.app` | `217.154.18.227` | Woodpecker CI on VPS-3 |
| `monitor.ittd.app` | `217.154.18.227` | GlitchTip on VPS-3 |
| `automate.ittd.app` | `217.154.18.227` | n8n on VPS-3 |

## VPS-2 Frontend

### Services

| Service | Purpose | Exposure |
|---|---|---|
| Caddy | Public reverse proxy and TLS termination | Public `80`/`443` |
| Static site | `www.ittd.app` landing page | Public through Caddy |
| CVForge | Main production app | Public through Caddy |
| Parsr | Document parsing service for CVForge | Private to CVForge unless explicitly public |
| AIACC | Standalone EU AI Act compliance app | Public through Caddy |

### Production Apps

| App | Domain | Runtime | Dependencies |
|---|---|---|---|
| CVForge | `cvforge.ittd.app` | VPS-2 monolith | Supabase, Parsr, LiteLLM, Unleash, GlitchTip |
| AIACC | `aiacc.ittd.app` | VPS-2 app | GlitchTip |

### Ports

| Port | Service | Access |
|---:|---|---|
| `22` | SSH | Admin only |
| `80` | Caddy HTTP | Public |
| `443` | Caddy HTTPS | Public |
| `2019` | Caddy admin API | Localhost only |
| App ports | CVForge, Parsr, AIACC | Localhost/container network behind Caddy |

## VPS-1 Backend

### Services

| Service | Purpose | Exposure |
|---|---|---|
| Supabase | CVForge auth, database, storage, realtime APIs | Through VPS-2 Caddy |
| LiteLLM | AI model proxy for CVForge | Private or through `proxy.ittd.app` |
| Unleash | Feature flags for CVForge | Private or admin-only through `flags.ittd.app` |
| Production Postgres | Product data store | Private network only |
| Infra Postgres | Infra/tooling data store | Private network only |
| Valkey | Cache and queue service | Private network only |

### LiteLLM

```text
CVForge -> LiteLLM -> OpenRouter -> selected AI models
```

The OpenRouter API key is stored in OpenBao and injected server-side. It must never be exposed to client-side code.

### Data Services

Run two separate Postgres services on VPS-1.

| Postgres service | Databases/users |
|---|---|
| Production Postgres | Supabase/CVForge, LiteLLM, Unleash |
| Infra Postgres | GlitchTip, n8n, Forgejo, Woodpecker |

Each app gets its own database, user, password, and minimum required privileges.

Production Postgres and Infra Postgres must have separate containers/services, volumes, credentials, backups, and restore procedures.

### Ports

| Port | Service | Access |
|---:|---|---|
| `22` | SSH | Admin only |
| `4000` | LiteLLM | VPS-2 Caddy / private network only |
| Supabase ports | Supabase API/Studio | VPS-2 Caddy / private network only |
| Unleash port | Unleash | VPS-2 Caddy / private network only |
| Production Postgres port | Production Postgres | Approved private hosts only |
| Infra Postgres port | Infra Postgres | Approved private hosts only |
| `6379` | Valkey | Approved private hosts only |

## VPS-3 Infra/DevOps

### Services

| Service | Purpose | Exposure |
|---|---|---|
| OpenBao | Central secrets manager | VPS-2 Caddy / admin/deployment-only |
| Forgejo | Source control | VPS-2 Caddy / team-only |
| Woodpecker CI | CI/CD | VPS-2 Caddy / team-only |
| Woodpecker agents | Build and deployment workers | Private |
| GlitchTip | Error tracking and uptime monitoring | VPS-2 Caddy / admin-only |
| n8n | Operational automation | VPS-2 Caddy / admin-only |
| Runbooks/deployment repo | Operational source of truth | Private |

### Ports

| Port | Service | Access |
|---:|---|---|
| `22` | SSH | Admin only |
| Tool ports | OpenBao, Forgejo, Woodpecker, GlitchTip, n8n | VPS-2 Caddy / VPN/admin sources only |

## Secrets

OpenBao on VPS-3 is the source of truth for runtime and deployment secrets.

Day-one flow:

```text
Admin/CI -> OpenBao -> deployment script -> server-side .env files -> Docker Compose services
```

Rules:

- Store secrets by environment and service, for example `prod/cvforge`, `prod/litellm`, `infra/forgejo`.
- Grant CI/deployment automation access only to required OpenBao paths.
- Generate `.env` files during deployment with restrictive permissions.
- Never commit secrets to the repository.
- Never print secrets in CI logs, n8n logs, shell history, or GlitchTip events.
- Rotate OpenRouter, Supabase, database, SMTP, and admin credentials through OpenBao.

## Monitoring And Error Tracking

GlitchTip on VPS-3 is the day-one monitoring and error-tracking service.

It handles:

- Sentry-compatible exception reporting from CVForge and AIACC.
- HTTP checks for public services.
- TCP checks for private services where reachable.
- SSL expiry checks.
- Notifications and webhooks.

n8n handles follow-up workflows:

- Formatted alert notifications.
- Forgejo issue creation.
- Scheduled health summaries.
- Manual-approved runbook actions.

## Network Security

Detailed policy: `Plan/03-network-firewall-policy.md`

Rules:

- Public `80`/`443` only on VPS-2.
- VPS-1 backend ports accept only VPS-2 Caddy and approved private/admin sources.
- VPS-3 tool ports accept only VPS-2 Caddy and approved private/admin sources.
- Databases are not public.
- Valkey is not public.
- Caddy admin API is localhost-only.
- Admin UIs require strong authentication and should be VPN/IP-restricted where possible.
- Use WireGuard for server-to-server traffic.

## TLS

Public TLS terminates at Caddy on VPS-2.

Preferred certificate model:

- Caddy-managed Let's Encrypt certificates on VPS-2.
- No public certificates on VPS-1 or VPS-3 unless direct public access is intentionally introduced.

Internal server-to-server traffic:

- Day one: HTTP over WireGuard/firewalled ports is acceptable.
- Stronger later: internal HTTPS using OpenBao PKI or another internal CA.

## Deployment

Deployment source:

```text
Forgejo -> Woodpecker -> agents -> VPS targets
```

Deployment rules:

- Pin production image versions where practical.
- Avoid automatic `latest` updates for production services.
- Scope deployment credentials narrowly.
- Keep production and infra deployment permissions separate.
- Use OpenBao for deployment secrets.

## Pre-Deployment Decisions

1. Decide whether Supabase is self-hosted on VPS-1 or externally hosted.
2. Configure WireGuard server-to-server networking from `Plan/06-wireguard-server-network.md`.
3. Finalize which admin domains are public behind authentication versus VPN-only.
4. Deploy OpenBao and define secret paths/policies.
5. Define backup and restore procedures for Production Postgres, Infra Postgres, OpenBao, and uploaded files.
6. Define DLP rules for OpenRouter prompts, GlitchTip events, logs, and uploaded documents.
