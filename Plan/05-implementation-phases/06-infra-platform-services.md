# Phase 6: Infra Platform Services

Status: **Phase 6 complete** — all four Infra platform services live

Goal: deploy company platform services on **VPS-3 Infra** (`ts-ionos-infra`), public via **Caddy on Frontend** over WireGuard — same pattern as Phase 5.

Primary references:

- `Plan/02-three-server-service-layout.md`
- `Plan/03-network-firewall-policy.md`
- `Plan/05-implementation-phases/04-backend-data-foundation.md` (Infra Postgres)
- `Plan/05-implementation-phases/05-backend-product-services.md` (patterns to reuse)

Estimated effort: **~1 service per session** (Ansible role + deploy + smoke test + doc update).

---

## Decisions (agreed)

| Topic | Choice |
|---|---|
| Host | All four services on **VPS-3 Infra** (`10.44.0.3`) |
| Public edge | **Frontend Caddy** → WireGuard → Infra service ports (no public Infra `:443`) |
| Database | **Infra Postgres on Backend** — `10.44.0.1:5433` (Phase 4), not a DB container on Infra |
| Secrets | **OpenBao-first** — `infra/*` paths, sync/bootstrap scripts on Infra (mirror Phase 5) |
| Network mode | Prefer **Docker host network** on Infra (Phase 4/5 lesson — avoids nftables FORWARD drops) |
| Woodpecker agents | Same Infra host initially; treat as **privileged** (Docker socket access) |
| Valkey | Backend `127.0.0.1:6379` only — use only if a service needs it (likely n8n optional later) |

---

## Already done (prerequisites)

- [X] OpenBao on Infra — `secrets.ittd.app` (Phase 3)
- [X] WireGuard mesh — Frontend `10.44.0.2` → Infra `10.44.0.3` → Backend `10.44.0.1`
- [X] Infra Postgres + DBs on **Backend** — `forgejo`, `woodpecker`, `glitchtip`, `n8n` (Phase 4)
- [X] Backend firewall — Infra WG IP allowed to `5433`
- [X] Caddy placeholders — `git`, `ci`, `monitor`, `automate` return 503 until deployed
- [X] Phase 5 patterns — OpenBao sync scripts, pinned images, `ansible/roles/*` layout

### Pre-flight (before service 1)

Run once; not a deployable service but blocks everything if wrong.

| # | Check | Command / action | Status |
|---|---|---|---|
| 0.1 | OpenBao unsealed | Infra: `bao status` or health via `secrets.ittd.app` | [X] |
| 0.2 | Infra Postgres reachable from Infra VPS | Infra: `nc -zv 10.44.0.1 5433` | [X] |
| 0.3 | OpenBao `infra/postgres/*` populated | Push from Backend if missing (Phase 4 scripts) | [X] |
| 0.4 | Docker on Infra | `ansible-playbook playbooks/docker.yml --limit infra` if needed | [X] |
| 0.5 | Infra firewall baseline | `ansible-playbook playbooks/firewall.yml --limit infra` | [X] |

**DB connection string pattern for all Phase 6 apps:**

```text
host=10.44.0.1  port=5433  user=<app>  database=<app>
password from OpenBao infra/postgres/<app>
```

---

## Implementation order

Deploy in this sequence. **Do not skip ahead** — each step unlocks the next.

```text
0. Pre-flight
1. Forgejo          git.ittd.app      — source control (no Phase 6 deps)
2. Woodpecker       ci.ittd.app       — needs Forgejo OAuth + webhooks
3. GlitchTip        monitor.ittd.app  — independent; before apps need monitoring
4. n8n              automate.ittd.app — automation; benefits from Forgejo + GlitchTip
```

### Why this order

| Order | Service | Rationale |
|---|---|---|
| **1** | **Forgejo** | Git is the foundation. Woodpecker clones from Forgejo; n8n can open Forgejo issues. Easiest to validate alone (Postgres + HTTP). |
| **2** | **Woodpecker** | CI/CD depends on Forgejo (OAuth app, repo webhooks). Deploy **server first**, then **agents**, then one harmless pipeline job. |
| **3** | **GlitchTip** | Error tracking is independent of CI. Deploy before Phase 7 so CVForge/AIACC can report errors on day one. |
| **4** | **n8n** | Operational automation last — workflows often call Forgejo APIs and react to GlitchTip/monitoring events. Old Frontend stack had n8n (`Old_Config/Automation/`) — reference only, redeploy fresh on Infra. |

---

## Public URLs & ports (target)

| URL | Service | Infra bind (planned) | Caddy upstream |
|---|---|---|---|
| `git.ittd.app` | Forgejo | `10.44.0.3:3000` | WG → `:3000` |
| `ci.ittd.app` | Woodpecker server | `10.44.0.3:8000` | WG → `:8000` |
| `monitor.ittd.app` | GlitchTip | `10.44.0.3:8080` | WG → `:8080` |
| `automate.ittd.app` | n8n | `10.44.0.3:5678` | WG → `:5678` |
| `secrets.ittd.app` | OpenBao | `10.44.0.3:8200` | already live |

Uncomment matching ports in `ansible/inventory/group_vars/infra.yml` → `firewall_tcp_ports_from_frontend` as each service goes live.

---

## Patterns (carry forward from Phase 5)

1. **Ansible role per service** — `ansible/roles/{forgejo,woodpecker,glitchtip,n8n}/`
2. **OpenBao sync script** — `sync-<service>-from-openbao.sh` in `/opt/cvforge/secrets/`
3. **Skeleton `.env`** in Git; runtime secrets from OpenBao only
4. **Host network** on Infra unless a component strictly needs bridge isolation
5. **If using bridge network** — apply Backend Phase 5 firewall lessons on Infra (`forward` egress + restart Docker after nftables reload)
6. **Per-service playbook tag** — extend `playbooks/infra.yml` or add `playbooks/infra-services.yml`
7. **Gateway + firewall in same session** as each service — Caddy route replaces 503 placeholder; Infra opens WG port for Frontend only
8. **Document in this file** after each service — status, quirks, OpenBao keys, validation checklist

---

## OpenBao secret map (Phase 6)

| Path | Keys (planned) | When |
|---|---|---|
| `infra/postgres/forgejo` | `host`, `port`, `user`, `password`, `database` | Phase 4 (push script) |
| `infra/postgres/woodpecker` | same | Phase 4 |
| `infra/postgres/glitchtip` | same | Phase 4 |
| `infra/postgres/n8n` | same | Phase 4 |
| `infra/Forgejo` | `Admin password` (required); `secret_key` (optional — generated on sync) | Service 1 — **operator done** |
| `infra/woodpecker` | `forgejo_client_id`, `forgejo_client_secret`, `agent_secret` (optional) | Service 2 — **operator** |
| `infra/glitchtip` | `secret_key`, `admin_username`, `admin_email`, `admin_password` | Service 3 — **operator** |
| `infra/n8n` | `encryption_key`, admin creds, webhook secrets | Service 4 bootstrap |
| `shared/smtp` | (existing) | n8n / GlitchTip email if needed |

---

# Service 1 — Forgejo

**Status:** [X] **Complete** — `15.0.2`, org `ittd`, test repo validated

| Item | Detail |
|---|---|
| URL | `https://git.ittd.app` |
| Role | `ansible/roles/forgejo/` |
| Image | `codeberg.org/forgejo/forgejo:15.0.2` |
| DB | `infra/postgres/forgejo` → `10.44.0.1:5433` |
| Sync script | `/opt/cvforge/secrets/sync-forgejo-from-openbao.sh` |
| Reference | `Old_Config/Infra/` (legacy layout only) |

### Operator prep (before Ansible)

- [X] Admin username: **`ittd-admin`** (Forgejo reserves `admin`)
- [X] Admin password: OpenBao **`infra` → `Forgejo`** → key **`Admin password`**
- [X] Default org name: **`ittd`** (created in UI)
- [X] Admin email: `noreply@ittd.app`
- [ ] `secret_key` in OpenBao `infra/Forgejo` — generated at first bootstrap if missing

**OpenBao path note:** App secrets at `infra/Forgejo` (capital **F** — KV paths are case-sensitive). DB creds at `infra/postgres/forgejo` (Phase 4).

### Ansible & deploy

```bash
cd ansible
ansible-playbook playbooks/infra-services.yml --limit infra --tags forgejo
ansible-playbook playbooks/gateway.yml --tags caddy    # git.ittd.app → 10.44.0.3:3000
ansible-playbook playbooks/firewall.yml --limit infra  # open :3000 from Frontend WG
```

On Infra — sync secrets, start, then bootstrap (skip install wizard if possible):

```bash
export BAO_TOKEN='<admin-or-root-token>'
sudo -E /opt/cvforge/secrets/sync-forgejo-from-openbao.sh
sudo docker compose -f /opt/cvforge/forgejo/docker-compose.yml up -d --force-recreate
sudo /opt/cvforge/secrets/bootstrap-forgejo.sh
```

If you already used the install wizard: still run `bootstrap-forgejo.sh` after sync to fix `SECRET_KEY` / `INSTALL_LOCK` and create `ittd-admin`.

**403 on sync:** `admin-policy` was created with `infra/*` but KV v2 reads use `infra/data/Forgejo`. Fix script updates policy to `infra/data/*` + `infra/metadata/*` (same for `prod/` and `shared/`).

**403 on fix script:** Policy writes need the **root token** from KeePass — admin userpass cannot update `sys/policies/acl/*`. `export BAO_TOKEN=<root-token>` then re-run fix script.

**Install wizard DB error (5432 refused):** Infra Postgres listens on **5433**. Forgejo install wizard ignores `FORGEJO__database__PORT` — put **`10.44.0.1:5433`** in the Host field (host:port in one field).

**502 after Install:** Usually `SECRET_KEY=REPLACE_AFTER_OPENBAO` in `.env`/`app.ini` plus `INSTALL_LOCK=false` causing crash loop. Run `sync-forgejo-from-openbao.sh` then `bootstrap-forgejo.sh`. Do **not** use username `admin` (reserved) — use `ittd-admin`.

**503 on sync:** OpenBao sealed — unseal with KeePass key (`bao operator unseal`). Do not restart Docker on Infra during service deploys without planning to unseal.

### Validation

- [X] `https://git.ittd.app` loads (HTTP 200 via Caddy)
- [X] Admin login works (`ittd-admin` + OpenBao `Admin password`)
- [X] Create org `ittd` + test repo
- [ ] DBeaver: `forgejo` DB has tables on `10.44.0.1:5433`
- [ ] Port `3000` not reachable from public internet (only via Caddy)
- [ ] Store generated `secret_key` in OpenBao `infra/Forgejo` (sync generated one on first run)

### Notes (fill after deploy)

```text
2026-06-08: Deployed via ansible/roles/forgejo (image 15.0.2, host network, :3000).
OpenBao: infra/Forgejo + infra/postgres/forgejo; KV v2 policy fix one-time.
Quirks: DB host 10.44.0.1:5433; bootstrap-forgejo.sh not install wizard; username ittd-admin.
Scripts: sync-forgejo-from-openbao.sh, bootstrap-forgejo.sh in /opt/cvforge/secrets/.
Validated: login, org ittd, test repo. Optional: store secret_key in OpenBao; DBeaver DB check.
```

---

# Service 2 — Woodpecker CI

**Status:** [X] **Complete** — server + agent, Forgejo OAuth, operator validated

| Item | Detail |
|---|---|
| URL | `https://ci.ittd.app` |
| Role | `ansible/roles/woodpecker/` |
| Image | `woodpeckerci/woodpecker-server:v3.15.0` + agent same tag |
| Depends on | Forgejo OAuth app at `git.ittd.app` |
| DB | `infra/postgres/woodpecker` → `10.44.0.1:5433` (port in `DATABASE_DATASOURCE` URL) |
| Sync script | `/opt/cvforge/secrets/sync-woodpecker-from-openbao.sh` |
| Sub-steps | 2a Server → 2b Agent → 2c Test pipeline |

### Operator prep — OpenBao (do this before deploy)

**1. Forgejo OAuth app** (as `ittd-admin` on https://git.ittd.app):

- **Site administration** → **Applications** → **Create OAuth2 Application**
- Name: `Woodpecker CI`
- **Redirect URI:** `https://ci.ittd.app/authorize` (exact)
- Copy **Client ID** and **Client Secret**

**2. OpenBao secret `infra/woodpecker`** (KV v2, lowercase path):

| Key | Required | How to get |
|---|---|---|
| `forgejo_client_id` | Yes | Forgejo OAuth app |
| `forgejo_client_secret` | Yes | Forgejo OAuth app |
| `agent_secret` | Optional | `openssl rand -hex 32` — sync generates one if missing; store for reuse |

**3. OpenBao `infra/postgres/woodpecker`** — should already exist from Phase 4 (`password` key). No action unless empty.

**Not in OpenBao** (Ansible defaults): `WOODPECKER_ADMIN=ittd-admin`, public URLs, ports, image tags.

**Forgejo lessons applied:** no `REPLACE_*` placeholders; DB port `5433` in postgres URL; `.env.skeleton` = config only; host network `10.44.0.3:8000` / `:9000`.

**Host-network quirks:** scratch server image — no container healthcheck; agent `WOODPECKER_HEALTHCHECK=false` (Forgejo owns `:3000`).

### Operator prep checklist

- [X] Forgejo OAuth app created (`https://ci.ittd.app/authorize`)
- [X] OpenBao `infra/woodpecker` populated (`forgejo_client_id`, `forgejo_client_secret`, `agent_secret`)
- [X] OpenBao `infra/postgres/woodpecker` has `password`
- [X] Agent model: single agent on Infra with Docker socket (privileged)

### Ansible & deploy

```bash
cd ansible
ansible-playbook playbooks/infra-services.yml --limit infra --tags woodpecker
ansible-playbook playbooks/gateway.yml
ansible-playbook playbooks/firewall.yml --limit infra
```

On Infra:

```bash
export BAO_TOKEN='<admin-token>'
sudo -E /opt/cvforge/secrets/sync-woodpecker-from-openbao.sh
sudo docker compose -f /opt/cvforge/woodpecker/docker-compose.yml up -d --force-recreate
```

Then open https://ci.ittd.app → login via Forgejo OAuth as `ittd-admin`.

### Validation

- [X] `https://ci.ittd.app` — login via Forgejo OAuth
- [X] Activate a test repo from Forgejo
- [X] Agent connected (green in UI)
- [X] Pipelines running (operator confirmed)
- [X] No secrets in build logs (OpenBao-only sync pattern)

### Notes (fill after deploy)

```text
2026-06-09: woodpecker-server + woodpecker-agent v3.15.0 on Infra host network.
OpenBao infra/woodpecker + infra/postgres/woodpecker; Forgejo OAuth redirect /authorize.
Deploy: sync-woodpecker-from-openbao.sh; Caddy ci.ittd.app → :8000; firewall :8000.
Fixed: no wget healthcheck on scratch image; WOODPECKER_HEALTHCHECK=false (Forgejo :3000).
Operator validated: OAuth login, agent alive, CI working.
```

---

# Service 3 — GlitchTip

**Status:** [X] **Complete** — operator validated

| Item | Detail |
|---|---|
| URL | `https://monitor.ittd.app` |
| Role | `ansible/roles/glitchtip/` |
| Image | `glitchtip/glitchtip:6.1.8` (web + worker) |
| DB | `infra/postgres/glitchtip` → `10.44.0.1:5433` in `DATABASE_URL` |
| Cache/queue | `VALKEY_URL=` empty — Postgres-backed (no Valkey on Infra) |
| Sync / bootstrap | `sync-glitchtip-from-openbao.sh`, `bootstrap-glitchtip.sh` |
| Consumers (Phase 7) | CVForge, AIACC SDK DSN |

### Operator prep — OpenBao

**1. Secret `infra/glitchtip`** (KV v2, lowercase):

| Key | Required | Notes |
|---|---|---|
| `admin_username` | Yes | e.g. `ittd-admin` |
| `admin_email` | Yes | e.g. `noreply@ittd.app` |
| `admin_password` | Yes | Django superuser password |
| `secret_key` | Optional | `openssl rand -hex 32` — sync generates if missing |

**2. `infra/postgres/glitchtip`** — Phase 4 (`password` key).

**3. Email (optional):** `shared/smtp` (Brevo) — if missing, sync uses `consolemail://` (logs only).

**4. After deploy (UI):** create org + projects for CVForge / AIACC; copy DSNs for Phase 7.

**Lessons applied:** no placeholders in templates; `.env.skeleton` = config only; host network `:8080`; bootstrap creates superuser (no install wizard).

### Operator prep checklist

- [X] OpenBao `infra/glitchtip` populated
- [X] OpenBao `infra/postgres/glitchtip` has `password`
- [ ] (Optional) `shared/smtp` for alert emails

### Ansible & deploy

```bash
cd ansible
ansible-playbook playbooks/infra-services.yml --limit infra --tags glitchtip
ansible-playbook playbooks/gateway.yml
ansible-playbook playbooks/firewall.yml --limit infra
```

On Infra:

```bash
export BAO_TOKEN='<admin-token>'
sudo -E /opt/cvforge/secrets/sync-glitchtip-from-openbao.sh
sudo /opt/cvforge/secrets/bootstrap-glitchtip.sh
```

### Validation

- [X] `https://monitor.ittd.app` — admin login
- [X] Create project; copy DSN for later Phase 7
- [ ] Send test event (Sentry SDK or curl) — event appears, secrets scrubbed
- [ ] DBeaver: `glitchtip` DB populated

### Notes (fill after deploy)

```text
2026-06-09: glitchtip 6.1.8 web + worker, host network :8080, Postgres queue (VALKEY_URL empty).
OpenBao infra/glitchtip + infra/postgres/glitchtip; bootstrap-glitchtip.sh for superuser.
monitor.ittd.app live. Operator confirmed working. DSNs ready for Phase 7.
```

---

# Service 4 — n8n

**Status:** [X] **Complete** — operator validated

| Item | Detail |
|---|---|
| URL | `https://automate.ittd.app` |
| Role | `ansible/roles/n8n/` |
| Image | `docker.n8n.io/n8nio/n8n:2.23.4` |
| DB | `infra/postgres/n8n` → `10.44.0.1:5433` via `DB_POSTGRESDB_*` |
| Env / sync | `sync-n8n-from-openbao.sh` → `/opt/cvforge/secrets/n8n.env` (not project `.env`) |
| Reference | `Old_Config/Automation/docker-compose.yml` (SMTP ideas only; no local Postgres, no basic-auth) |

### Operator prep — OpenBao

**1. Secret `infra/N8N`** (KV v2 — **capital N**, case-sensitive like `infra/Forgejo`):

| Key | Required | Notes |
|---|---|---|
| `encryption_key` | Yes | `openssl rand -hex 32` — sync generates if missing (store after first sync) |
| `owner_email` | Optional | Pre-seed instance owner (skip first-login wizard) |
| `owner_password` | Optional | Plaintext in OpenBao — sync bcrypt-hashes to `N8N_INSTANCE_OWNER_PASSWORD_HASH` |
| `owner_first_name` | Optional | Default `ITTD` |
| `owner_last_name` | Optional | Default `Admin` |

If `owner_email` / `owner_password` are omitted, complete owner setup in the n8n UI on first visit.

**2. `infra/postgres/n8n`** — Phase 4 (`password` key).

**3. Email (optional):** `infra/shared/smtp` (Brevo) — if missing, SMTP env vars are omitted.

**Lessons applied:** no placeholders; host network `N8N_LISTEN_ADDRESS=10.44.0.3`; `N8N_PROXY_HOPS=1`; port `5433` in `DB_POSTGRESDB_PORT`; data dir uid **1000** (`node`); secrets in `n8n.env` with **quoted** `$` values (Compose interpolates bcrypt); OpenBao path `infra/N8N` (capital N).

### Operator prep checklist

- [X] OpenBao `infra/N8N` populated (`encryption_key`, owner creds)
- [X] OpenBao `infra/postgres/n8n` has `password`
- [X] `infra/shared/smtp` for email notifications

### Ansible & deploy

```bash
cd ansible
ansible-playbook playbooks/infra-services.yml --limit infra --tags n8n
ansible-playbook playbooks/gateway.yml
ansible-playbook playbooks/firewall.yml --limit infra
```

On Infra:

```bash
export BAO_TOKEN='<admin-token>'
sudo -E /opt/cvforge/secrets/sync-n8n-from-openbao.sh
sudo docker compose -f /opt/cvforge/n8n/docker-compose.yml up -d --force-recreate
```

Then open https://automate.ittd.app — log in as pre-seeded owner or complete first-time setup.

### Validation

- [X] `https://automate.ittd.app` — owner setup / login
- [ ] Create trivial workflow (manual trigger → Set node)
- [ ] Workflows do not log secrets
- [ ] DBeaver: `n8n` DB populated
- [ ] (Optional) Forgejo issue-creation workflow stub

### Notes (fill after deploy)

```text
2026-06-09: n8n 2.23.4, host network :5678, Postgres on Backend :5433.
OpenBao infra/N8N + infra/postgres/n8n + infra/shared/smtp; secrets/n8n.env (quoted $ for Compose).
Fixed: data/ chown 1000:1000; remove project .env; bcrypt hash corruption from $ interpolation.
automate.ittd.app live. Operator confirmed working.
```

---

## Ansible work (overall)

Current `playbooks/infra.yml` only runs `openbao` + `monitoring` stub. Phase 6 will add:

| Deliverable | Path |
|---|---|
| Infra services playbook | `playbooks/infra-services.yml` (new) |
| Forgejo role | `ansible/roles/forgejo/` |
| Woodpecker role | `ansible/roles/woodpecker/` |
| GlitchTip role | `ansible/roles/glitchtip/` |
| n8n role | `ansible/roles/n8n/` |
| Caddy routes | `roles/caddy/templates/Caddyfile.j2` — replace 503 block per host |
| Firewall | `inventory/group_vars/infra.yml` — enable ports incrementally |
| Static site | `roles/caddy/files/www/index.html` — flip badges to **Live** per service |

---

## Security rules

- Forgejo and Woodpecker: strong passwords; Woodpecker via Forgejo OAuth only
- Woodpecker agents: privileged — scope OpenBao policies; no prod deploy keys on agents until needed
- n8n: no secrets in workflow logs; use OpenBao/credentials for webhooks
- GlitchTip: scrub request bodies, AI prompts, and PII where possible
- All Infra UIs: team/admin access via Caddy TLS; no direct public Infra ports

---

## Phase 6 complete — validation summary

Mark each when the service block above is done:

- [X] Pre-flight (0.1–0.5)
- [X] Service 1 — Forgejo
- [X] Service 2 — Woodpecker (server + agent + test job)
- [X] Service 3 — GlitchTip
- [X] Service 4 — n8n
- [X] All four URLs live on `www.ittd.app` service directory
- [X] Infra ports not publicly reachable (Frontend WG only)
- [X] OpenBao `infra/*` paths documented per service

**Phase 7** (next): wire CVForge / AIACC to Supabase, LiteLLM, Unleash, GlitchTip DSN.

---

## Session log

Record date and outcome after each service deploy:

| Date | Service | Outcome |
|---|---|---|
| 2026-06-08 | Pre-flight | **Complete** — 0.1–0.5 all pass |
| 2026-06-08 | Forgejo | **Complete** — git.ittd.app, org ittd, test repo |
| 2026-06-09 | Woodpecker | **Complete** — ci.ittd.app, OAuth, agent, pipelines |
| 2026-06-09 | GlitchTip | **Complete** — monitor.ittd.app, admin login, projects/DSN |
| 2026-06-09 | n8n | **Complete** — automate.ittd.app, owner setup, editor live |
