# Phase 7: Production Apps

Status: **Parsr live** — CVForge next

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

**Status:** [X] **Complete** — API + UI deployed

| Item | Detail |
|---|---|
| URL | `https://parsr.ittd.app` (UI) |
| API (public) | `https://parsr.ittd.app/api/v1/*` via Caddy |
| API (CVForge) | `http://parsr:3001` on `gateway_default` |
| Role | `ansible/roles/parsr/` |
| Images | `axarev/parsr:master` (API), `axarev/parsr-ui-localhost:latest` (UI) |
| UI patch | `app.js` — `localhost:3001` → `/api/v1` for same-origin proxy |
| Data | `./pipeline` volume (parsed output) |
| Gateway auth | Caddy HTTP basic auth — `prod/parsr` → `sync-parsr-gateway-auth-from-openbao.sh` |

### Gateway authentication (required)

Parsr UI and the public `/api/v1` path are protected by **Caddy basic auth**. CVForge uses internal `http://parsr:3001` and is not affected.

**OpenBao `prod/parsr`:**

| Key | Required | Notes |
|---|---|---|
| `gateway_username` | Yes | e.g. `ittd-admin` |
| `gateway_password` | Yes | Strong password (plaintext in OpenBao; sync hashes via `caddy hash-password`) |

```bash
export BAO_TOKEN='<admin-token>'
sudo -E /opt/cvforge/secrets/sync-parsr-gateway-auth-from-openbao.sh
sudo docker compose -f /opt/cvforge/gateway/docker-compose.yml restart caddy
```

Until sync runs, `parsr.ittd.app` returns **503** (placeholder snippet).

### Architecture

```text
Browser → Caddy → parsr-ui:80          (static GUI)
Browser → Caddy → parsr:3001/api/v1/*  (REST API)
CVForge → parsr:3001/api/v1/*          (internal, Phase 7 CVForge)
```

Stock `parsr-ui-localhost` hardcodes `http://localhost:3001/api/v1` in client JS; Ansible patches to relative `/api/v1` so the UI works over HTTPS.

### Ansible & deploy

```bash
cd ansible
ansible-playbook playbooks/apps.yml --limit frontend --tags parsr
ansible-playbook playbooks/gateway.yml
```

### Validation

- [X] `https://parsr.ittd.app` — UI loads
- [X] `https://parsr.ittd.app/api/v1/default-config` — API responds
- [ ] Upload test document in UI — pipeline completes
- [ ] CVForge `PARSR_SERVICE_URL=http://parsr:3001` (when CVForge deployed)

### Notes

```text
2026-06-09: parsr:master + parsr-ui-localhost on gateway_default.
Caddy path-split /api/v1* → API, /* → UI; patched app.js for remote browsers.
Caddy basic auth via prod/parsr gateway_username/password. CVForge internal API unchanged.
```

---

# Service 3 — CVForge

**Status:** [ ] Deploy from **CVForge project** (image rebuild required)

**Handoff doc for CVForge repo:** [`Plan/cvforge-deployment-reference.md`](../cvforge-deployment-reference.md) — topology, URLs, env mapping, OpenBao paths, checklist.

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
| Parsr role | `ansible/roles/parsr/` |
| Caddy routes | `roles/caddy/templates/Caddyfile.j2` |

## Security rules

- Parsr public path requires Caddy basic auth; rotate via OpenBao + sync script.
- Production image versions pinned where practical.
- GlitchTip DSN and API keys only via OpenBao sync scripts.

## Phase 7 progress

- [X] Service 1 — AIACC
- [X] Service 2 — Parsr
- [ ] Service 3 — CVForge
- [ ] All production URLs live on `www.ittd.app` service directory
