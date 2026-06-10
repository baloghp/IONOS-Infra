# Phase 3: OpenBao And Secrets

Status: **Completed** (2026-06-06) — UI live at `secrets.ittd.app`; MFA deferred to before production secrets

Goal: establish Infra as the secrets source of truth before deploying data and application services.

Primary references:

- `Plan/02-three-server-service-layout.md`
- `Plan/03-network-firewall-policy.md`

## Decisions (agreed)

| Topic | Choice |
|---|---|
| Human MFA | TOTP on `userpass` — **deferred** (enable before production secrets) |
| Unseal | Manual after reboot (no auto-unseal yet) |
| Unseal shards | 1-of-1 held by operator (KeePass) |
| First secrets | `prod/test` placeholder in Phase 3; real OpenRouter/DB creds in Phases 4–5 |

## Ansible deploy

From `ansible/` on the control node:

```bash
# 1. Docker + OpenBao on Infra
ansible-playbook playbooks/openbao.yml

# 2. Infra firewall (8200 from Frontend over WireGuard)
ansible-playbook playbooks/firewall.yml --limit infra

# 3. Caddy route secrets.ittd.app → 10.44.0.3:8200
ansible-playbook playbooks/gateway.yml
```

Equivalent tag-based run (requires Docker already on Infra):

```bash
ansible-playbook playbooks/docker.yml --limit infra
ansible-playbook playbooks/infra.yml --tags openbao
```

### What Ansible manages

- `/opt/cvforge/openbao/` — Compose, `openbao.hcl`, data, logs
- Image `openbao/openbao:2.4.1`, bind `10.44.0.3:8200` (WireGuard only)
- `api_addr` = `https://secrets.ittd.app` (TLS at Caddy on Frontend)
- Reference bootstrap script: `/opt/cvforge/openbao/bootstrap-openbao.sh`

### What stays manual

Init, unseal, MFA, policies beyond bootstrap, and all secret values.

## Manual bootstrap (operator checklist)

SSH to Infra via Tailscale (`ts-ionos-infra`). Container name: `openbao`.

### 1. Initialize and unseal

```bash
# One unseal key (1-of-1) — store key + root token in KeePass immediately
docker exec -it openbao bao operator init -key-shares=1 -key-threshold=1

# Pass key as argument (NOT interactive prompt — base64 +/= breaks hidden paste)
docker exec openbao bao operator unseal '<unseal-key-from-init>'

docker exec openbao bao status
# expect: "Sealed": false

export BAO_TOKEN='<root-token-from-init>'
docker exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN="$BAO_TOKEN" openbao bao status

# sudo drops env vars — use -E to keep BAO_TOKEN
sudo -E /opt/cvforge/openbao/bootstrap-openbao.sh
```

After reboot:

```bash
docker exec openbao bao operator unseal '<unseal-key-from-keepass>'
```

**Unseal troubleshooting:** `cipher: message authentication failed` = wrong key (typo/truncated paste), not a broken vault. `key is shorter than minimum 16 bytes` = incomplete paste. Always copy the full base64 line including trailing `=`, and use single quotes around the key.

### 2. Run bootstrap script (mounts, audit, userpass, admin policy)

Bootstrap uses `http://127.0.0.1:8200` inside the container (not the WireGuard IP).

```bash
export BAO_TOKEN='<root-token>'
sudo -E /opt/cvforge/openbao/bootstrap-openbao.sh
```

Audit logging is **declarative** in `openbao.hcl` (OpenBao 2.4+ blocks `bao audit enable` via API). Ansible manages the `audit "file" "cvforge-audit"` stanza; restart + unseal activates it.

Or run the same steps by hand (script echoes TOTP steps).

### 3. Create admin user

```bash
docker exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN="$BAO_TOKEN" -it openbao \
  bao write auth/userpass/users/admin policies=admin-policy password='<STRONG_PASSWORD>'
```

### 4. TOTP MFA (deferred — skip for now)

Enable before storing real production credentials (Phases 4–5). Until then, admin `userpass` + strong password only.

**Order matters when you do enable it:** enroll TOTP *before* login enforcement, or admin cannot log in.

```bash
# A) Create TOTP method (save method_id from output)
docker exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN="$BAO_TOKEN" openbao \
  bao write identity/mfa/method/totp name=admin-totp issuer=ITTD-OpenBao

# B) Login as admin (password only — enforcement not yet enabled)
docker exec -e BAO_ADDR=http://127.0.0.1:8200 -it openbao \
  bao login -method=userpass username=admin
# BAO_TOKEN is now the admin token inside this shell session

# C) Generate + validate TOTP enrollment (scan barcode/url in authenticator app)
docker exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN="$BAO_TOKEN" openbao \
  bao write identity/mfa/method/totp/generate method_id=<method_id>
docker exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN="$BAO_TOKEN" openbao \
  bao write identity/mfa/method/totp/validate method_id=<method_id> code=<6-digit-from-app>

# D) Find userpass accessor, then enforce MFA on all userpass logins
docker exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN="$BAO_TOKEN" openbao \
  bao auth list -format=json
docker exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN="$BAO_TOKEN" openbao \
  bao write identity/mfa/login-enforcement/admin-enforce \
    mfa_method_ids=<method_id> auth_method_accessors=<userpass_accessor>
```

Test at `https://secrets.ittd.app` — sign in with admin + TOTP code.

### 5. Phase 3 test secret

```bash
docker exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN="$BAO_TOKEN" openbao \
  bao kv put prod/test message=phase3-ok phase=3
```

### 6. Revoke routine use of root token

Store root token in KeePass for break-glass only. Day-to-day: `bao login -method=userpass` + TOTP.

## Secret path layout

KV v2 mounts (created by bootstrap):

```text
prod/     → cvforge, aiacc, supabase, litellm, unleash (Phase 4–7)
infra/    → forgejo, woodpecker, glitchtip, n8n, postgres, valkey (Phase 6+)
shared/   → smtp
```

## Validation

- [X] `http://10.44.0.3:8200/v1/sys/health?...&uninitcode=200` returns `initialized:false, sealed:true` (pre-init)
- [X] `https://secrets.ittd.app/v1/sys/health?...` returns HTTP 200 through Caddy
- [X] `https://secrets.ittd.app` OpenBao UI usable (KV mounts: `prod/`, `infra/`, `shared/`)
- [ ] Admin login requires password + TOTP (deferred)
- [ ] `bao kv put/get prod/test` smoke test
- [X] Audit log declarative in `openbao.hcl` (`/opt/cvforge/openbao/logs/audit.log`)
- [ ] Unseal key + root token + admin password in KeePass; not in Git

## Break-glass

1. Tailscale SSH to `ts-ionos-infra`
2. `docker exec -it openbao bao operator unseal` if sealed after reboot
3. Root token from KeePass only if admin user/MFA unavailable
4. Document incident; rotate affected credentials after use

## Notes

- CLI inside container is `bao` (not `vault`).
- OpenBao listens HTTP on WireGuard; public HTTPS only through Caddy.
- OpenBao uses **Docker host network** (not port-publish) so cross-VPS traffic hits nftables INPUT, not FORWARD — avoids 502 from Caddy.
- Woodpecker read-only policy and real service secrets land in Phases 4–6.
