# Phase 2: Frontend Gateway, TLS, And Static Site

Status: **Completed** (2026-06-06)

Goal: make VPS-2 the only public web gateway and terminate public HTTPS with Caddy.

Primary references:

- `Plan/02-three-server-service-layout.md`
- `Plan/03-network-firewall-policy.md`

## TLS decision

- **IONOS SSL Starter Wildcard** `*.ittd.app` (Sectigo), not Let's Encrypt.
- Cert files live on control node: `ansible/files/frontend/ssl/` (gitignored).
- Caddy uses `tls /etc/ssl/bundle.pem /etc/ssl/private.key`.
- Reissued cert valid **2026-06-06 → 2026-12-03**.
- Renewal procedure and slot inventory: `Plan/tls-certificate-rotation.md`.

## Manual DNS Work

Point these records to VPS-2 public IP `217.154.18.227` (if not already):

- `ittd.app`
- `www.ittd.app`
- `cvforge.ittd.app`
- `aiacc.ittd.app`
- `supabase.ittd.app`
- `studio.ittd.app`
- `proxy.ittd.app`
- `flags.ittd.app`
- `secrets.ittd.app`
- `git.ittd.app`
- `ci.ittd.app`
- `monitor.ittd.app`
- `automate.ittd.app`

## Ansible Work

Install Docker/Compose on VPS-2:

```bash
cd ansible
ansible-playbook playbooks/docker.yml --limit frontend
```

Deploy the gateway:

```bash
cd ansible
ansible-playbook playbooks/gateway.yml
```

Re-apply Frontend firewall (DOCKER-USER rules) after Docker:

```bash
ansible-playbook playbooks/firewall.yml --limit frontend
```

### Role layout

| Path | Purpose |
|------|---------|
| `roles/docker/` | Docker Engine + Compose plugin |
| `roles/caddy/` | Gateway at `/opt/cvforge/gateway` |
| `files/frontend/ssl/` | IONOS cert, intermediates, private key (gitignored) |

### Gateway on VPS

```text
/opt/cvforge/gateway/
  docker-compose.yml
  Caddyfile
  platform-status.py
  ssl/bundle.pem
  ssl/private.key
  www/index.html
  www/platform-status.json   # written by timer / playbook
```

Caddy publishes **80** and **443** only. Admin API is `localhost:2019` inside the container (not on public interface).

### Platform health & update status (2026-10-12)

`www.ittd.app` shows live **Up/Down** badges and version badges (**green** when current, **amber** `running → latest` when behind).

| Piece | Role |
|---|---|
| `roles/caddy/files/platform-status.py` | Probes public hostnames; compares pins / live versions to GitHub, Codeberg, or Docker Hub |
| `platform-status.timer` | systemd: 2 min after boot, then every **30 min** |
| `www/platform-status.json` | JSON consumed by `index.html` (same basic-auth as the directory) |
| Playbook | `gateway.yml` deploys checker + runs one refresh at the end |

Manual refresh:

```bash
ssh ts-ionos-frontend 'sudo systemctl start platform-status.service'
```

Version sources (when no public version API):

| Card | Running version | Latest |
|---|---|---|
| LiteLLM | OpenAPI `info.version` | GitHub `BerriAI/litellm` |
| n8n / OpenBao / Forgejo / … | Live API or Ansible **pin** in the script | Upstream releases |
| Supabase API | GoTrue pin (`2.x`) | GitHub `supabase/auth` |
| Supabase Studio | Studio image date (`YYYY.MM.DD`) | Docker Hub `supabase/studio` |
| AIACC / Parsr | Health only (no useful public semver) | — |

When bumping a pinned image in a role `defaults/main.yml`, update the matching `pinned` value in `platform-status.py` or the badge will stay on the old pin until the next script edit.

## Validation (2026-06-06)

- [X] Caddy starts cleanly (`docker ps` healthy).
- [X] IONOS wildcard TLS loaded (no Let's Encrypt).
- [X] `80`/`443` open; `2019` not public.
- [X] `www.ittd.app` loads static site over HTTPS.
- [X] `www.ittd.app` Caddy basic auth (2026-06-09) — `prod/www` + `sync-www-gateway-auth-from-openbao.sh`.
- [X] Static site service directory — live/planned status, OpenBao link (2026-06-06).
- [X] Health + update badges from `platform-status.json` (2026-10-12).
- [X] Placeholder `503` blocks for undeployed app/infra hostnames.
- [X] `ittd.app` redirect to `www` (verify in browser after DNS).

## Notes And Decisions

| Hostname | Phase 2 behaviour |
|----------|-------------------|
| `www.ittd.app` | Static service directory — Caddy basic auth (`prod/www`) |
| `ittd.app` | Redirect → `www.ittd.app` |
| `cvforge`, `aiacc`, `parsr` | 503 until Phase 7 |
| Backend subdomains | 503 until Phase 5 |
| Infra subdomains | 503 until Phase 6 |

**Docker + nftables:** Caddy role restarts Docker before `compose up` so iptables `DOCKER` chain exists after nftables.

**www basic auth:** OpenBao `prod/www` keys `gateway_username`, `gateway_password` → `/opt/cvforge/gateway/auth/www.caddy` via `sync-www-gateway-auth-from-openbao.sh`. Other hostnames use per-service auth (e.g. `prod/parsr`).
