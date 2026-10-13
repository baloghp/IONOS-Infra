# Phase 5: Backend Product Services

Status: **Complete** — deployed and fully validated (2026-06-07)

Goal: deploy **self-hosted Supabase**, **LiteLLM**, and **Unleash** on VPS-1 Backend, public via Caddy on Frontend.

Primary references:

- `Plan/02-three-server-service-layout.md`
- `Plan/03-network-firewall-policy.md`
- `Plan/05-implementation-phases/04-backend-data-foundation.md` (prerequisite)

Estimated implementation session: **~2–4 hours** (Ansible + deploy + smoke tests), after operator prep below is done.

---

## Decisions (agreed)

| Topic | Choice |
|---|---|
| Supabase | **Self-hosted** on VPS-1 — Auth, API, Storage, Realtime, Studio |
| Supabase database | Existing **Production Postgres** `postgres-prod` — DB/user `supabase` (Phase 4) |
| LiteLLM | VPS-1, DB `litellm`, port `4000`, OpenRouter upstream |
| Unleash | VPS-1, DB `unleash` |
| SMTP | **Brevo** (EU, France) — 300 emails/day free; signup, confirm, **password reset** |
| Auth | Email + password only; confirmations + reset **on** when SMTP verified |
| OAuth | Deferred (Google etc. later) |
| Storage | Local volume on Backend (`/opt/cvforge/supabase/storage`) — migrate to S3 later if needed |
| OpenBao MFA | Still deferred |
| DNS | Service subdomains already point to Frontend `217.154.18.227` (Phase 2) |

---

## Already done (Phases 3–4)

- [X] OpenBao at `secrets.ittd.app`
- [X] `postgres-prod` with DBs: `supabase`, `litellm`, `unleash`
- [X] `postgres-infra`, Valkey on Backend
- [X] DB credentials in OpenBao `prod/postgres/*`, `prod/valkey`
- [X] Caddy TLS, WireGuard mesh, static site service directory
- [X] DBeaver / Redis Insight admin access from dev machine

---

## Public URLs (after Phase 5)

| URL | Service | Audience |
|---|---|---|
| `supabase.ittd.app` | Supabase API (Kong) | CVForge SDK / apps |
| `studio.ittd.app` | Supabase Studio | **Admin** — DB & auth UI |
| `proxy.ittd.app` | LiteLLM | CVForge AI proxy |
| `flags.ittd.app` | Unleash | **Admin** — feature flags |

Caddy on Frontend → WireGuard → `10.44.0.1` on Backend. No public DB ports.

---

# Part A — You (operator, before the session)

Complete these **before** we run Ansible. Blockers marked **required**.

## A1. Brevo SMTP (required for password reset) — **DONE** (2026-06-07)

- [X] 1. Sign up at [brevo.com](https://www.brevo.com) (free plan).
- [X] 2. **Transactional** → **SMTP & API** → **Generate SMTP key**.
- [X] 3. **Senders & Domains** → add domain **`ittd.app`**.
- [X] 4. Add DNS records in **IONOS** (SPF, DKIM, DMARC as Brevo shows).
- [X] 5. Wait until Brevo shows domain **Verified**.
- [X] 6. Add sender: `noreply@ittd.app` (or `auth@ittd.app`).
- [X] 7. Store in **OpenBao** path `shared/smtp`:

   | Key | Value |
   |---|---|
   | `host` | `smtp-relay.brevo.com` |
   | `port` | `587` |
   | `user` | **SMTP login** from Brevo → SMTP & API → SMTP tab (e.g. `7xxxxx@smtp-brevo.com`) — **not** your Gmail/account email |
   | `password` | Brevo SMTP key (`xsmtpsib-…`, not API key or login password) |
   | `from_email` | `noreply@ittd.app` |
   | `from_name` | `ITTD` |

- [X] 8. Backup SMTP key in **KeePass**.

**Fallback during session:** If DNS not verified yet, we can deploy with `mailer_autoconfirm=true` temporarily (no reset emails) and enable SMTP same day once verified.

## A2. OpenRouter (required before LiteLLM) — **DONE** (2026-06-07)

- [X] 1. Account at [openrouter.ai](https://openrouter.ai).
- [X] 2. Create API key.
- [X] 3. Store in **OpenBao** `prod/litellm` → key `openrouter_api_key`.

## A3. Unleash admin (required before Unleash) — **DONE** (2026-06-07)

- [X] 1. Choose a strong admin password.
- [X] 2. Store in **OpenBao** `prod/unleash` → key `admin` (or `password` at `prod/unleash/admin`).

## A4. KeePass / access (always) — **DONE** (2026-06-07)

- [X] OpenBao unseal key accessible (reboot may seal vault)
- [X] `BAO_TOKEN` or admin userpass for bootstrap scripts
- [X] Tailscale / SSH to `ts-ionos-backend` works

## A5. Optional before session

- [X] Backend disk: **233 GB** total, **228 GB** free on `/` (`ts-ionos-backend`, 2026-06-07) — ample for local Supabase storage
- [ ] Pi-hole / DNS flush if testing new routes from LAN

## Operator checklist (printable)

```text
[x] Brevo account created
[x] ittd.app verified in Brevo
[x] shared/smtp in OpenBao
[x] OpenRouter API key in OpenBao
[x] Unleash admin password in OpenBao
[x] KeePass updated
[x] OpenBao unsealed / access ready
[x] Backend disk OK (228 GB free)
```

---

# Part B — Together (implementation session)

We implement Ansible roles, deploy, run bootstrap scripts, update Caddy + static site, and smoke-test.

## B1. Ansible — new roles & playbooks

| Deliverable | Path (planned) |
|---|---|
| Supabase role | `ansible/roles/supabase/` — official stack, **external** Postgres |
| LiteLLM role | `ansible/roles/litellm/` — reuse patterns from `Old_Config/LiteLLM/` |
| Unleash role | `ansible/roles/unleash/` |
| Backend playbook | extend `playbooks/backend.yml` or `playbooks/backend-services.yml` |
| Caddy routes | `roles/caddy/templates/Caddyfile.j2` — replace 503 placeholders |
| Firewall | `inventory/group_vars/backend.yml` — Frontend → WG ports |
| Static site | `roles/caddy/files/www/index.html` — Live badges |

**Patterns (same as Phase 3–4):**

- Docker **host network** where needed (avoid nftables FORWARD drops)
- Bind services to `127.0.0.1` or `10.44.0.1` only
- Secrets from OpenBao via env files / bootstrap scripts (never Git)
- Pin container image versions

## B2. Self-hosted Supabase stack

External Postgres — **no** bundled Supabase DB container.

| Container / service | Purpose |
|---|---|
| Kong | API gateway → `supabase.ittd.app` |
| GoTrue | Auth — email/password, SMTP via `shared/smtp` |
| PostgREST | REST API |
| Realtime | Websockets |
| Storage | Local filesystem volume |
| Studio | Admin UI → `studio.ittd.app` |
| meta | Studio metadata |

Connection: `127.0.0.1:5432`, database `supabase`, creds from `prod/postgres/supabase`.

Generated at bootstrap → OpenBao `prod/supabase/` (JWT secret, anon key, service_role key, etc.).

GoTrue (with SMTP):

- Email + password signup
- Email confirmation (configurable)
- **Password reset emails**
- No OAuth until later

## B3. LiteLLM

- Image: `ghcr.io/berriai/litellm:v1.105.0` (pinned in `ansible/roles/litellm/defaults/main.yml`)
- DB: `prod/postgres/litellm` from OpenBao
- Port: `4000` on `10.44.0.1` or `127.0.0.1` + Caddy
- OpenRouter key from `prod/litellm` → `openrouter_api_key`
- Optional: Valkey from `prod/valkey`
- Upgrade notes and lessons: **§ LiteLLM image upgrades (2026-10-12)** below

## B4. Unleash

- DB: `prod/postgres/unleash` from OpenBao
- Admin UI → `flags.ittd.app`
- Bootstrap admin from `prod/unleash/admin`

## B5. Deploy commands (session)

```bash
cd ansible

# Backend product services
ansible-playbook playbooks/backend-services.yml   # or backend.yml --tags product

# Caddy routes (Frontend)
ansible-playbook playbooks/gateway.yml

# Firewall (Backend WG ports)
ansible-playbook playbooks/firewall.yml --limit backend
```

## B6. Manual steps during session (both of us)

| Step | Who | Action |
|---|---|---|
| Unseal OpenBao if sealed | You | `docker exec openbao bao operator unseal ...` on Infra |
| Run Supabase bootstrap | Together | Script pushes JWT/keys to `prod/supabase/` |
| Run LiteLLM bootstrap | Together | If master key / UI creds generated |
| Re-run deploy after secrets | We | Ansible reads updated OpenBao paths |
| Smoke test signup + reset email | You | Test inbox after Brevo live |
| Smoke test Studio | You | `https://studio.ittd.app` |
| Smoke test LiteLLM | Together | Health + one OpenRouter call |
| Smoke test Unleash | You | `https://flags.ittd.app` login |

## B7. Implementation order (session agenda)

| # | Block | ~time | Depends on |
|---|---|---|---|
| 1 | Supabase Ansible role + deploy | 60–90 min | `shared/smtp`, `prod/postgres/supabase` |
| 2 | Caddy `supabase` + `studio` | 15 min | Supabase up |
| 3 | Auth smoke test (signup + reset) | 15 min | Brevo verified |
| 4 | LiteLLM role + deploy + Caddy | 30–45 min | OpenRouter key |
| 5 | Unleash role + deploy + Caddy | 30–45 min | Unleash admin password |
| 6 | Firewall + static site Live | 15 min | All services up |
| 7 | Validation checklist | 15 min | — |

---

## OpenBao secret map

| Path | Provided by | When |
|---|---|---|
| `prod/postgres/supabase` | Phase 4 | Done |
| `prod/postgres/litellm` | Phase 4 | Done |
| `prod/postgres/unleash` | Phase 4 | Done |
| `prod/valkey` | Phase 4 | Done |
| **`shared/smtp`** | **You (Brevo)** | **Before Supabase** |
| `prod/supabase/` | `init-supabase.sh` (first time) + **`sync-supabase-from-openbao.sh`** (runtime) | During session |
| `prod/litellm/` | Bootstrap + **you (OpenRouter)** | Before LiteLLM |
| `prod/unleash/` | **You (admin)** + bootstrap | Before Unleash |

---

## Validation — Phase 5 complete

- [X] `https://supabase.ittd.app` — Kong responds (HTTP 401 without key — expected)
- [X] `https://studio.ittd.app` — Studio via Kong basic-auth (HTTP 401 without credentials)
- [X] Signup + **password reset email** received (Brevo)
- [X] `https://proxy.ittd.app/health/liveliness` — LiteLLM healthy (HTTP 200)
- [X] `https://flags.ittd.app` — Unleash admin login
- [X] OpenRouter proxy call (LiteLLM API with master key)
- [X] DBeaver: schemas/tables in `supabase`, `litellm`, `unleash` DBs
- [X] Postgres/Valkey bind localhost/WG only; backend FORWARD fixed for Docker Kong/Studio
- [X] Static site updated — Phase 5 services **Live** on `www.ittd.app`
- [X] OpenBao paths populated (`prod/supabase`, `prod/litellm`, `prod/unleash`, `shared/smtp`)

**Phase 7** (later): CVForge app wired to these URLs.

---

## Final setup & retrospective (2026-06-07)

This section records **what we actually deployed**, **why key choices were made**, and **what we had to fix** during a long validation session. Use it as the operational reference for Phase 5.

### Architecture as deployed

```text
Internet
  → Frontend Caddy (217.154.18.227, TLS)
    → WireGuard 10.44.0.1 (Backend)
      → Supabase Kong :8000   (API + Studio behind basic-auth)
      → LiteLLM         :4000 (host network)
      → Unleash         :4242 (host network)

Backend (ts-ionos-backend, 82.165.44.144)
  postgres-prod :5432  (127.0.0.1 + 172.17.0.1 — external to Supabase compose)
  valkey        :6379  (127.0.0.1)
  /opt/cvforge/supabase/   Docker compose stack (no bundled Postgres)
  /opt/cvforge/litellm/    Docker, host network
  /opt/cvforge/unleash/    Docker, host network
  /opt/cvforge/secrets/    Bootstrap + sync scripts (OpenBao pull)

Infra (ts-ionos-infra, 10.44.0.3)
  OpenBao :8200  — all Phase 5 runtime secrets
```

| Public URL | Caddy upstream | Backend listener | Notes |
|---|---|---|---|
| `supabase.ittd.app` | `10.44.0.1:8000` | Kong `:8000` | App/SDK API; requires `anon_key` or `service_role_key` |
| `studio.ittd.app` | `10.44.0.1:8000` | Kong `:8000` | **Not** direct `:3000` — Kong dashboard basic-auth |
| `proxy.ittd.app` | `10.44.0.1:4000` | LiteLLM host network | API: `master_key`; UI: `ui_username` / `ui_password` |
| `flags.ittd.app` | `10.44.0.1:4242` | Unleash host network | UI: `admin` + OpenBao `prod/unleash` → `admin` |

**Why Frontend terminates TLS and proxies over WireGuard:** single public edge (Phase 2 design), Backend ports firewalled to Frontend WG IP only, no public Postgres.

**Why LiteLLM and Unleash use host network:** avoids nftables `forward` policy `drop` biting container egress and simplifies binding to `10.44.0.1` / `127.0.0.1`.

**Why Supabase uses Docker bridge + external Postgres:** official self-hosted stack expects multiple containers; we reuse Phase 4 `postgres-prod` instead of a bundled DB container.

### Ansible deliverables

| Role | Path | Playbook |
|---|---|---|
| Supabase | `ansible/roles/supabase/` | `playbooks/backend-services.yml --tags supabase` |
| LiteLLM | `ansible/roles/litellm/` | `playbooks/backend-services.yml --tags litellm` |
| Unleash | `ansible/roles/unleash/` | `playbooks/backend-services.yml --tags unleash` |
| Caddy routes | `ansible/roles/caddy/templates/Caddyfile.j2` | `playbooks/gateway.yml` |
| Firewall | `ansible/roles/firewall/` | `playbooks/firewall.yml --limit backend` |

Pinned images (see each role `defaults/main.yml`):

- Supabase Studio `2026.04.27-sha-5f60601`, Kong `3.9.1`, GoTrue `v2.186.0`, PostgREST `v14.8`, Realtime `v2.76.5`, Storage `v1.48.26`
- LiteLLM `ghcr.io/berriai/litellm:v1.105.0`
- Unleash `unleashorg/unleash-server:6.9.0`

### OpenBao-first secrets model

**Principle:** Git/Ansible deploy **skeleton** `.env` files and scripts; **runtime secrets** live in OpenBao and are pulled on the host.

| Path | Keys | Used by |
|---|---|---|
| `shared/smtp` | `host`, `port`, `user`, `password`, `from_email`, `from_name` | GoTrue (Brevo) |
| `prod/supabase` | `url`, `studio_url`, `anon_key`, `service_role_key`, `jwt_secret`, `dashboard_username`, `dashboard_password` | Kong, Studio, apps |
| `prod/litellm` | `master_key`, `salt_key`, `ui_username`, `ui_password`, `openrouter_api_key` | LiteLLM API + UI + OpenRouter |
| `prod/unleash` | `admin` | Unleash bootstrap / UI |
| `prod/postgres/{supabase,litellm,unleash}` | DB passwords | Postgres connections |
| `prod/valkey` | password | LiteLLM cache (optional) |

**`POSTGRES_PASSWORD` in `/opt/cvforge/supabase/.env` is special:** internal Supabase stack credential (roles like `supabase_auth_admin`). It is **not** in `prod/supabase` — generated at first `init-supabase.sh`, preserved across `sync-supabase-from-openbao.sh` runs.

**Credential confusion we resolved (read this before debugging logins):**

| UI / API | Wrong guess | Correct source |
|---|---|---|
| Studio basic-auth | Postgres password | `prod/supabase` → `dashboard_username` / `dashboard_password` |
| LiteLLM UI | `master_key` | `prod/litellm` → `ui_username` / `ui_password` |
| LiteLLM API | `ui_password` | `prod/litellm` → `master_key` |
| Unleash UI | `db_prod_unleash` | `prod/unleash` → `admin` |
| Brevo SMTP | Account email / API key | `shared/smtp` → `user` = `*@smtp-brevo.com`, `password` = `xsmtpsib-…` |

### Operator scripts on Backend (`/opt/cvforge/secrets/`)

| Script | When to use |
|---|---|
| `sync-supabase-from-openbao.sh` | After any OpenBao change to `prod/supabase` or `shared/smtp`; rebuilds `.env` |
| `verify-supabase-smtp.sh` | Test Brevo from `.env`; with `BAO_TOKEN` compares OpenBao vs `.env` first |
| `repair-supabase-passwords.sh` | Align `supabase_auth_admin` / `authenticator` / `storage_admin` with `.env` `POSTGRES_PASSWORD` |
| `repair-supabase-db.sh` | Full DB init repair (first-time breakage) |
| `init-supabase.sh` | **First time only** — generate keys, migrate, push to OpenBao |
| `bootstrap-litellm.sh` / `reset-litellm.sh` | Pull LiteLLM secrets from OpenBao |
| `reset-unleash-admin.sh` | Delete stale Unleash admin user, re-bootstrap from OpenBao |

Typical secret rotation:

```bash
export BAO_TOKEN=<token>
sudo -E /opt/cvforge/secrets/sync-supabase-from-openbao.sh   # or litellm/unleash equivalent
sudo docker compose -f /opt/cvforge/supabase/docker-compose.yml up -d --force-recreate auth
sudo -E /opt/cvforge/secrets/verify-supabase-smtp.sh
```

### Supabase-specific design choices

1. **Studio via Kong, not `:3000`**
   - **Problem:** Studio was reachable without auth when Caddy pointed at `:3000`.
   - **Fix:** Caddy `studio.ittd.app` → Kong `:8000` (dashboard basic-auth). Studio container has **no host port publish**.

2. **Postgres host `host.docker.internal`**
   - Compose `extra_hosts: host.docker.internal:host-gateway` maps to `172.17.0.1` where `postgres-prod` listens.
   - **Why not `172.18.0.1`:** compose bridge is `172.18.0.0/16`; Postgres binds `172.17.0.1` (docker0 gateway).

3. **`SNIPPETS_MANAGEMENT_FOLDER` + volume**
   - Studio warned without it; added `/app/snippets` mount in compose.

4. **`GOTRUE_MAILER_EXTERNAL_HOSTS`**
   - `supabase.ittd.app,studio.ittd.app` — correct links in auth emails.

### Firewall & Docker networking (critical lessons)

Three separate issues blocked Supabase; each looked like “API error” or “SMTP timeout” in the UI.

| # | Symptom | Root cause | Fix (Ansible) |
|---|---|---|---|
| 1 | SQL OK, Auth unhealthy, Studio API Zod errors | Compose bridge `172.18.0.0/16` → Postgres on `172.17.0.1` blocked on **input** (`docker0` only) | `iifname "br-*" accept` on Backend **input**; `pg_hba` allow `172.18.0.0/16` |
| 2 | `verify-supabase-smtp.sh` OK on host, GoTrue mail 504 timeout | Container egress blocked on **forward** (policy drop) | `iifname "veth*"` / `br-*` / `docker0` → `ens6` accept on Backend **forward** |
| 3 | Intermittent egress after `firewall.yml` | nftables reload dropped Docker **MASQUERADE** iptables rules | `firewall_restart_docker_after_reload: true` on Backend — restart Docker after nftables reload |

**Why host SMTP test passed but Studio failed:** `verify-supabase-smtp.sh` runs Python on the **host** (egress OK). GoTrue sends mail from **inside** `supabase-auth` (needs forward + MASQUERADE).

**Brevo IP allowlist:** authorize Backend public IP `82.165.44.144` before enabling “block unauthorized IPs for SMTP keys”.

### Brevo SMTP checklist (validated)

- Domain `ittd.app` verified (SPF, DKIM, DMARC)
- Sender `noreply@ittd.app` configured
- `shared/smtp` in OpenBao synced to `/opt/cvforge/supabase/.env`
- SMTP login is `add934001@smtp-brevo.com` (**not** personal Gmail)
- Password is `xsmtpsib-…` SMTP key (**not** API key `xkeysib-…`)
- After OpenBao edit: always run `sync-supabase-from-openbao.sh` + recreate `auth`

### Validation completed

All items confirmed 2026-06-07:

- Supabase API + Studio (SQL, Table Editor, Auth admin)
- Public signup + password reset email (Brevo)
- LiteLLM health, UI login, OpenRouter `chat/completions` via `proxy.ittd.app`
- Unleash admin login + flag management
- DBeaver: `supabase`, `litellm`, `unleash` databases
- `www.ittd.app` static site Phase 5 **Live** badges

### If something breaks again

| Symptom | First checks |
|---|---|
| Studio API / Auth errors | `docker ps` — is `supabase-auth` healthy? `docker logs supabase-auth` |
| Mail timeout in UI | `sudo -E verify-supabase-smtp.sh`; from auth container: can reach `smtp-relay.brevo.com:587`? |
| SMTP 535 | Wrong Brevo `user` or stale `.env` — sync from OpenBao |
| Egress dead after firewall deploy | `iptables -t nat -L POSTROUTING` — MASQUERADE present? `sudo systemctl restart docker` |
| LiteLLM 401 on UI | Use `ui_password`, not `master_key` |
| LiteLLM UI banner about env credentials | Expected on ≥1.104 — create a personal `proxy_admin`, then set `disable_env_credential_login` (see below) |
| LiteLLM playbook skips recreate / `.env` is skeleton | Do **not** recreate until secrets restored — see LiteLLM upgrade lessons |
| Unleash login fails after redeploy | `reset-unleash-admin.sh` |

### LiteLLM image upgrades (2026-10-12)

**Done:** `main-v1.79.1-stable` → `ghcr.io/berriai/litellm:v1.105.0` (latest stable at upgrade time; `1.106` was still RC).

**Tag naming:** LiteLLM dropped the old `main-vX.Y.Z-stable` Docker tags. Pin reproducible tags as `v1.105.0` or `1.105.0` (same digest). Prefer content pins over `:latest` / `:main-stable`.

**Healthcheck:** newer images have **no `wget`**. Compose probe uses Python `urllib` against `/health/liveliness`. Raise `start_period` (120s) so Prisma migrations can finish before Docker marks the container unhealthy.

**Deploy:**

```bash
cd ansible
ansible-playbook playbooks/backend-services.yml --tags litellm
```

Role behaviour now:

1. Write `config.yaml` / compose always.
2. Write `.env` **skeleton only when the file is missing** (never overwrite a live OpenBao-backed `.env`).
3. If `.env` still contains `REPLACE_AFTER_OPENBAO`, try restore from any LiteLLM container that still has real env vars.
4. `docker compose pull` + `up -d` only when secrets are present; otherwise **fail** with the bootstrap command.
5. Does **not** restart the Docker daemon on every LiteLLM run (that used to bounce the old container onto a wiped `.env`).

**If secrets were wiped and no container still has them:**

```bash
ssh ts-ionos-backend
export BAO_TOKEN='…'   # from KeePass — not the literal string <token>
sudo -E /opt/cvforge/secrets/bootstrap-litellm.sh
sudo docker compose -f /opt/cvforge/litellm/docker-compose.yml up -d --force-recreate
```

Then re-run the playbook if compose/config still need syncing.

#### Lessons learned (do not repeat)

| Mistake | What happened | Rule going forward |
|---|---|---|
| Ansible `template` of skeleton `.env` every run | Live OpenBao secrets replaced with `REPLACE_AFTER_OPENBAO`; playbook set `bootstrap_pending` and **skipped** recreate while Docker restart brought the old image back | Skeletons: `force: false` / only when missing (Supabase pattern). Runtime secrets only from OpenBao sync/bootstrap scripts |
| Folded YAML `>-` for a boolean `set_fact` | Value became string `"\nTrue"`; `\| bool` coerced to **False** (Ansible deprecation warning); restore skipped; compose ran with skeleton env → **502** | Boolean facts: one-line `"{{ expr }}"`, never `>-` / `\|` for bools |
| Recreate while `.env` was still a skeleton | New image booted without `LITELLM_MASTER_KEY` / DB URL | Gate `compose up` on pending flag; **fail** loudly; restore from container or OpenBao first |
| Running playbooks from repo root | Empty inventory + roles not found | Always `cd ansible` so `ansible.cfg` loads |
| Healthcheck still using `wget` | Container permanently `unhealthy` on new images | Prefer Python/curl already in the image; verify after bumps |
| Jumping many minor versions | Long Prisma migrate at first boot; proxy down until done | Treat major LiteLLM bumps as a short maintenance window; watch `docker logs litellm` |

#### Behaviour notes on ≥1.104 / 1.105

- **Master key:** refuse weak/empty `LITELLM_MASTER_KEY` at boot (use OpenBao `prod/litellm` → `master_key`).
- **Config ownership:** keys declared in `config.yaml` are file-owned; Admin UI cannot override them.
- **UI env login banner:** `UI_USERNAME` / `UI_PASSWORD` still work but are bootstrap-only. Create a personal `proxy_admin` (Internal Users → Invite), confirm login, then set `general_settings.disable_env_credential_login: true` and recreate. Reversible by removing the flag. Do **not** enable before a passworded admin exists.
- **Decision models (e.g. OpenRouter `typesafe/jev-*`):** not chat models. Call `POST https://proxy.ittd.app/v1/systemone` (or `/v1/decisions` for OpenAI Decisions shape). Chat Completions returns 400 pointing at OpenRouter `/api/alpha/decisions` — that path is upstream OpenRouter, not a route on this proxy.

#### Pin bump checklist (any product image)

**Mandatory:** after changing a pin, redeploy **both** the service **and** the gateway. `www.ittd.app` badges are baked from `platform_image_pins` at gateway deploy time. The 30‑minute timer only re-probes health/latest — it does **not** reload pins from Git. Skipping `gateway.yml` leaves the directory page on the old version (hit this with n8n: public `/rest/settings` no longer returns `versionCli`, so the badge is pin-only).

1. Set the new version in `ansible/inventory/group_vars/all.yml` → `platform_image_pins.<service>` (single source of truth for roles + status page).
2. Confirm the service role image uses that pin (e.g. `n8n_image: "...{{ platform_image_pins.n8n }}"`, LiteLLM likewise).
3. Ensure compose **pulls** before `up` (LiteLLM / n8n do).
4. Confirm healthcheck still works in the new image.
5. Confirm `.env` / secrets path is not overwritten by Ansible.
6. From `ansible/`, deploy the service playbook (`--tags …`).
7. **Also** run `ansible-playbook playbooks/gateway.yml` (or at least refresh the checker after deploy: it rewrites `platform-status.py` with the new pins and runs one status pass).
8. Smoke test the service URL; on `www.ittd.app` confirm the version badge matches (green when current, or `running → latest` when still behind upstream).

---

## Deferred (not Phase 5)

- OAuth (Google, GitHub, …)
- OpenBao MFA for human admins
- S3-compatible Supabase Storage migration
- CVForge monolith deploy (`cvforge.ittd.app`)
- IP/VPN restriction on Studio / flags (app auth first; harden later)

