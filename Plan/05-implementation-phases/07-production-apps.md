# Phase 7: Production Apps

Status: **AIACC live** — CVForge and Parsr next

Goal: deploy the production applications on VPS-2 behind Caddy.

Primary references:

- `Plan/02-three-server-service-layout.md`
- `Plan/03-network-firewall-policy.md`

## Applications

VPS-2 runs:

- CVForge.
- Parsr.
- AIACC.

CVForge is a monolith and uses Supabase, Parsr, LiteLLM, Unleash, and GlitchTip.

AIACC is a small public Next.js app without its own backend service.

## Deployment order

| # | App | URL | Notes |
|---|-----|-----|-------|
| 1 | **AIACC** | `aiacc.ittd.app` | Standalone; no Backend deps — deploy first |
| 2 | Parsr | (internal) | CVForge dependency |
| 3 | CVForge | `cvforge.ittd.app` | Supabase, LiteLLM, Unleash, GlitchTip |

---

# Service 1 — AIACC

**Status:** [X] **Complete** — operator validated

| Item | Detail |
|---|---|
| URL | `https://aiacc.ittd.app` |
| Role | `ansible/roles/aiacc/` |
| Image | `baloghp/ai-act-compliance:latest` (Next.js 15, port 3000) |
| Network | `gateway_default` — Caddy reverse-proxies `aiacc:3000` |
| Env | `/opt/cvforge/secrets/aiacc.env` (seeded from skeleton; no OpenBao required) |
| Health | `GET /` (image has no `/api/health` route in current build) |
| GlitchTip | Optional `prod/aiacc` → `glitchtip_dsn` when app is instrumented |

### Operator prep — OpenBao (optional)

**`prod/aiacc`** — only when Sentry/GlitchTip SDK is added to the app image:

| Key | Notes |
|---|---|
| `glitchtip_dsn` | Project DSN from monitor.ittd.app |

### Ansible & deploy

```bash
cd ansible
ansible-playbook playbooks/apps.yml --limit frontend --tags aiacc
ansible-playbook playbooks/gateway.yml
```

Optional GlitchTip DSN after OpenBao populated:

```bash
export BAO_TOKEN='<admin-token>'
sudo -E /opt/cvforge/secrets/sync-aiacc-from-openbao.sh
sudo docker compose -f /opt/cvforge/aiacc/docker-compose.yml up -d --force-recreate
```

### Validation

- [X] `https://aiacc.ittd.app` — app loads over HTTPS
- [X] App responds 200 via Caddy
- [ ] GlitchTip test event (after SDK + DSN in image)

### Notes

```text
2026-06-09: AIACC on gateway_default; Caddy aiacc:3000; no secrets required for v1 image.
Image has no Sentry SDK yet — GlitchTip DSN wiring deferred until app rebuild.
```

---

# Service 2 — Parsr

**Status:** [ ] Not started

---

# Service 3 — CVForge

**Status:** [ ] Not started

---

## Deployment Model

Use Forgejo and Woodpecker for application CI/CD.

Use Ansible for:

- Server layout.
- Compose deployment structure.
- Environment file rendering.
- Caddy route management.
- Controlled rollback helpers.

## Ansible Work

```bash
cd ansible
ansible-playbook playbooks/apps.yml
```

| Deliverable | Path |
|---|---|
| Apps playbook | `playbooks/apps.yml` |
| AIACC role | `ansible/roles/aiacc/` |
| Caddy routes | `roles/caddy/templates/Caddyfile.j2` |

## Security rules

- Parsr stays private unless direct public access is explicitly required.
- Production image versions pinned where practical.
- GlitchTip DSN and API keys only via OpenBao sync scripts.

## Phase 7 progress

- [X] Service 1 — AIACC
- [ ] Service 2 — Parsr
- [ ] Service 3 — CVForge
- [ ] All production URLs live on `www.ittd.app` service directory
