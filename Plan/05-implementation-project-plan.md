# Implementation project plan

Step-by-step project plan to build the CVForge 3-VPS infrastructure.

Architecture: `Plan/02-three-server-service-layout.md`
Firewall policy: `Plan/03-network-firewall-policy.md`
Admin VPN step zero: `Plan/04-admin-vpn-step-zero.md`
Server-to-server WireGuard: `Plan/06-wireguard-server-network.md`
Ansible baseline: `Plan/01-ansible-intro.md`

## Operating Model

Ansible is the infrastructure-as-code control plane for this setup.

Default rule:

- Manual steps are allowed only for provider-console actions, first SSH bootstrap, initial VPN enrollment, DNS changes, and break-glass recovery.
- Repeatable VPS configuration is done through Ansible playbooks and roles.
- Docker and Docker Compose are installed through Ansible.
- Compose files, Caddy config, firewall config, service directories, backup jobs, and operational scripts are deployed through Ansible.
- Container image updates are deliberate Ansible runs, not automatic Watchtower updates.
- Production images are pinned where practical; updates happen by changing the pinned version and running the relevant Ansible playbook.
- `www.ittd.app` platform-status checker surfaces health and “running → latest” lag; keep its pins aligned when bumping images.
- OpenBao-backed `.env` files must never be overwritten by Ansible skeleton templates on every run (seed only when missing). See LiteLLM upgrade lessons in Phase 5.

Target automation layout:

```text
ansible/
  inventory/hosts.yml
  inventory/group_vars/
  host_vars/
  playbooks/
    site.yml
    hardening.yml
    wireguard.yml
    docker.yml
    gateway.yml
    backend.yml
    infra.yml
    apps.yml
    update-containers.yml
  roles/
    base
    ssh
    firewall
    wireguard
    docker
    caddy
    postgres
    valkey
    openbao
    monitoring
```

## Phase Execution Files

The checklist below is the dependency overview. Detailed execution notes live in:

| Phase | Execution file |
|---:|---|
| 0 | `Plan/05-implementation-phases/00-admin-vpn-and-hardening.md` |
| 1 | `Plan/05-implementation-phases/01-network-and-firewall-baseline.md` |
| 2 | `Plan/05-implementation-phases/02-frontend-gateway-tls-static-site.md` |
| 3 | `Plan/05-implementation-phases/03-openbao-and-secrets.md` |
| 4 | `Plan/05-implementation-phases/04-backend-data-foundation.md` |
| 5 | `Plan/05-implementation-phases/05-backend-product-services.md` |
| 6 | `Plan/05-implementation-phases/06-infra-platform-services.md` |
| 7 | `Plan/05-implementation-phases/07-production-apps.md` |
| 8 | `Plan/05-implementation-phases/08-monitoring-dlp-operational-checks.md` |
| 9 | `Plan/05-implementation-phases/09-final-hardening-and-acceptance.md` |

## Phase 0: Admin VPN And VPS Hardening

- [X] Confirm IONOS console access works for all three VPS.
- [X] Confirm current SSH access works for all three VPS.
- [X] Install Tailscale on Fedora workstation.
- [X] Install Tailscale on VPS-1 Backend.
- [X] Install Tailscale on VPS-2 Frontend.
- [X] Install Tailscale on VPS-3 Infra.
- [X] Name Tailscale nodes: `ts-ionos-backend`, `ts-ionos-frontend`, `ts-ionos-infra`, `rog-fedora`.
- [X] Test SSH to all VPS over Tailscale IPs.
- [X] Add VPN SSH aliases to local SSH config.
- [X] Update Ansible inventory to use VPN aliases or VPN IPs.
- [X] Create Ansible `ansible.cfg`.
- [X] Create Ansible inventory groups: `ionos`, `backend`, `frontend`, `infra`.
- [X] Verify Ansible connectivity with `ansible all -m ping`.
- [X] Create Ansible base/hardening playbook.
- [X] Create non-root admin user on all VPS.
- [X] Configure sudo for admin user.
- [X] Install SSH keys for admin user.
- [X] Disable password SSH after key and VPN access are verified.
- [X] Disable direct root SSH after admin user access is verified.
- [X] Install baseline packages on all VPS.
- [X] Enable automatic security updates.
- [X] Install and configure fail2ban or equivalent SSH protection.
- [X] Confirm time sync is enabled on all VPS.
- [X] Confirm system logs are persistent.
- [X] Keep public SSH open only until VPN and emergency access are proven.

## Phase 1: Network And Firewall Baseline

**Status: Completed** (2026-05-18). Execution guide: `Plan/05-implementation-phases/01-network-and-firewall-baseline.md`.

- [X] Create Ansible WireGuard role using `Plan/06-wireguard-server-network.md`.
- [X] Configure WireGuard server-to-server network through Ansible.
- [X] Assign WireGuard IPs: Backend `10.44.0.1`, Frontend `10.44.0.2`, Infra `10.44.0.3`.
- [X] Verify WireGuard handshakes between all three VPS.
- [X] Verify VPS-1 can ping `10.44.0.2` and `10.44.0.3`.
- [X] Verify VPS-2 can ping `10.44.0.1` and `10.44.0.3`.
- [X] Verify VPS-3 can ping `10.44.0.1` and `10.44.0.2`.
- [X] Configure IONOS firewall: VPS-2 allows public `80/tcp` and `443/tcp`.
- [X] Configure IONOS firewall: VPS-1 exposes no public app/database ports.
- [X] Configure IONOS firewall: VPS-3 exposes no public HTTP/HTTPS edge.
- [X] Create Ansible firewall role.
- [X] Configure host firewall on VPS-1 through Ansible.
- [X] Configure host firewall on VPS-2 through Ansible.
- [X] Configure host firewall on VPS-3 through Ansible.
- [X] Ensure public SSH is closed or limited to emergency/admin VPN policy (Backend/Infra: Tailscale only; Frontend: public 22 open by decision — Step 1.10).
- [X] Ensure Docker-published ports cannot bypass firewall policy (`firewall_manage_docker_user` on Frontend).
- [X] Verify externally that only intended public ports are reachable.
- [X] Verify VPS-2 can reach required WireGuard upstreams on VPS-1.
- [X] Verify VPS-2 can reach required WireGuard upstreams on VPS-3.

## Phase 2: Frontend Gateway, TLS, And Static Site

**Status: Completed** (2026-06-06). Execution guide: `Plan/05-implementation-phases/02-frontend-gateway-tls-static-site.md`.

- [X] Create Ansible Docker role.
- [X] Install Docker/Compose runtime on VPS-2 through Ansible.
- [X] Create standard service directory layout on VPS-2 through Ansible (`/opt/cvforge/gateway`).
- [X] Create Ansible Caddy/gateway role.
- [X] Deploy Caddy on VPS-2 through Ansible.
- [ ] Point `ittd.app` DNS to VPS-2 `217.154.18.227`.
- [ ] Point service subdomains to VPS-2 `217.154.18.227`.
- [X] Configure TLS with IONOS wildcard cert (not automatic Let's Encrypt).
- [X] Configure `ittd.app` redirect to `www.ittd.app`.
- [X] Deploy minimal static site for `www.ittd.app`.
- [X] Static site on `www.ittd.app` is public (no gateway basic auth; apps authenticate individually).
- [X] Add shortcut links on the static site for production and admin services.
- [X] Ensure Caddy admin API is bound to localhost only.
- [X] Configure Caddy access logs.
- [X] Configure basic security headers.
- [X] Verify HTTPS certificate issuance (IONOS/Sectigo wildcard).
- [X] Verify `www.ittd.app` loads over HTTPS without gateway basic auth.

## Phase 3: OpenBao And Secrets

- [X] Install Docker/Compose runtime on VPS-3 through Ansible.
- [X] Create standard service directory layout on VPS-3 through Ansible.
- [X] Create Ansible OpenBao role.
- [X] Deploy OpenBao on VPS-3 through Ansible.
- [X] Route `secrets.ittd.app` through VPS-2 Caddy to VPS-3 OpenBao.
- [X] Restrict OpenBao to WireGuard bind (`10.44.0.3:8200`); public access only via Caddy + OpenBao auth.
- [X] Initialize OpenBao.
- [ ] Store unseal/recovery material offline in KeePass or equivalent.
- [X] Enable OpenBao audit logging (declarative `openbao.hcl`).
- [X] Configure human admin authentication (userpass; MFA deferred).
- [ ] Configure MFA for human admin access (deferred — before Phases 4–5 secrets).
- [X] Create secret path structure: `prod/*`, `infra/*`, `shared/*`.
- [X] Create initial policies for admins.
- [ ] Create read-only deployment policy for Woodpecker/deployment automation.
- [ ] Store initial secrets for OpenRouter, SMTP, database users, Supabase, LiteLLM, Unleash, GlitchTip, Forgejo, Woodpecker, and n8n.
- [ ] Test reading a non-production secret from deployment automation.
- [ ] Document break-glass access procedure.

## Phase 4: Backend Data Foundation

- [X] Install Docker/Compose runtime on VPS-1 through Ansible.
- [X] Create standard service directory layout on VPS-1 through Ansible.
- [X] Create Ansible Postgres role.
- [X] Create Ansible Valkey role.
- [X] Deploy Production Postgres through Ansible.
- [X] Deploy Infra Postgres through Ansible.
- [X] Deploy Valkey through Ansible.
- [X] Create Production Postgres databases/users for Supabase/CVForge, LiteLLM, and Unleash.
- [X] Create Infra Postgres databases/users for GlitchTip, n8n, Forgejo, and Woodpecker.
- [ ] Store database credentials in OpenBao (push scripts on Backend — manual step).
- [ ] Configure private network access to Production Postgres.
- [ ] Configure private network access to Infra Postgres.
- [ ] Configure private network access to Valkey.
- [ ] Verify databases are not reachable from the public internet.
- [ ] Verify Valkey is not reachable from the public internet.
- [ ] Define backup locations and retention.
- [ ] Implement backup jobs for Production Postgres.
- [ ] Implement backup jobs for Infra Postgres.
- [ ] Test restore for Production Postgres.
- [ ] Test restore for Infra Postgres.

## Phase 5: Backend Product Services

- [ ] Create Ansible backend-services role.
- [ ] Deploy Supabase through Ansible or finalize external Supabase decision.
- [ ] Route `supabase.ittd.app` through VPS-2 Caddy.
- [ ] Route `studio.ittd.app` through VPS-2 Caddy with admin-only access.
- [ ] Deploy LiteLLM on VPS-1 through Ansible.
- [ ] Connect LiteLLM to Production Postgres.
- [ ] Configure LiteLLM OpenRouter upstream.
- [ ] Store OpenRouter key in OpenBao.
- [ ] Route `proxy.ittd.app` through VPS-2 Caddy if public access is required.
- [ ] Deploy Unleash on VPS-1 through Ansible.
- [ ] Connect Unleash to Production Postgres.
- [ ] Route `flags.ittd.app` through VPS-2 Caddy with admin-only access.
- [ ] Verify CVForge can reach Supabase over private/service URL.
- [ ] Verify CVForge can reach LiteLLM over private/service URL.
- [ ] Verify CVForge can reach Unleash over private/service URL.

## Phase 6: Infra Platform Services

- [ ] Create Ansible infra-services role.
- [ ] Deploy Forgejo on VPS-3 through Ansible.
- [ ] Connect Forgejo to Infra Postgres.
- [ ] Route `git.ittd.app` through VPS-2 Caddy.
- [ ] Create initial organization/repositories.
- [ ] Deploy Woodpecker CI on VPS-3 through Ansible.
- [ ] Connect Woodpecker to Forgejo.
- [ ] Connect Woodpecker to Infra Postgres.
- [ ] Route `ci.ittd.app` through VPS-2 Caddy.
- [ ] Deploy Woodpecker agents through Ansible.
- [ ] Restrict Woodpecker deployment secrets through OpenBao policies.
- [ ] Deploy GlitchTip on VPS-3 through Ansible.
- [ ] Connect GlitchTip to Infra Postgres.
- [ ] Configure GlitchTip Valkey usage if needed.
- [ ] Route `monitor.ittd.app` through VPS-2 Caddy.
- [ ] Deploy n8n on VPS-3 through Ansible.
- [ ] Connect n8n to Infra Postgres.
- [ ] Route `automate.ittd.app` through VPS-2 Caddy.
- [ ] Configure n8n alert workflows from GlitchTip.

## Phase 7: Production Apps

- [ ] Create Ansible production-apps role.
- [ ] Prepare CVForge deployment repository in Forgejo.
- [ ] Prepare AIACC deployment repository in Forgejo.
- [ ] Prepare deployment secrets in OpenBao.
- [ ] Create Woodpecker pipeline for CVForge.
- [ ] Create Woodpecker pipeline for AIACC.
- [ ] Deploy Parsr on VPS-2 through Ansible/Woodpecker.
- [ ] Deploy CVForge on VPS-2 through Ansible/Woodpecker.
- [ ] Deploy AIACC on VPS-2 through Ansible/Woodpecker.
- [ ] Route `cvforge.ittd.app` through local VPS-2 Caddy.
- [ ] Route `aiacc.ittd.app` through local VPS-2 Caddy.
- [ ] Keep Parsr private unless direct public access is required.
- [ ] Configure CVForge environment from OpenBao-generated secrets.
- [ ] Configure AIACC environment from OpenBao-generated secrets.
- [ ] Add GlitchTip SDK/DSN to CVForge.
- [ ] Add GlitchTip SDK/DSN to AIACC.
- [ ] Verify CVForge login/auth path.
- [ ] Verify CVForge document parsing path.
- [ ] Verify CVForge LiteLLM/OpenRouter path.
- [ ] Verify CVForge feature flag path.
- [ ] Verify AIACC public app path.

## Phase 8: Monitoring, DLP, And Operational Checks

- [ ] Configure GlitchTip uptime checks for public domains.
- [ ] Configure GlitchTip checks for Supabase, LiteLLM, Unleash, Forgejo, Woodpecker, and n8n.
- [ ] Configure TCP checks for Production Postgres, Infra Postgres, and Valkey where reachable.
- [ ] Configure SSL expiry checks.
- [ ] Configure GlitchTip alert notifications.
- [ ] Configure n8n alert workflow from GlitchTip webhook.
- [ ] Configure Forgejo issue creation for sustained outages.
- [ ] Define GlitchTip event retention.
- [ ] Configure SDK scrubbing for PII/secrets/request bodies.
- [ ] Define OpenRouter prompt/document DLP rules.
- [ ] Verify secrets do not appear in CI logs.
- [ ] Verify secrets do not appear in n8n logs.
- [ ] Verify secrets do not appear in GlitchTip events.

## Phase 9: Final Hardening And Acceptance

- [ ] Confirm public internet can reach only VPS-2 `80/tcp` and `443/tcp`.
- [ ] Confirm VPS-1 service/database ports are not publicly reachable.
- [ ] Confirm VPS-3 tool ports are not publicly reachable.
- [ ] Confirm SSH works over VPN.
- [ ] Disable or heavily restrict public SSH.
- [ ] Confirm IONOS console break-glass access.
- [ ] Confirm Caddy routes all required domains.
- [ ] Confirm admin domains require authentication and/or VPN/IP restriction.
- [ ] Confirm OpenBao MFA is enforced for human admins.
- [ ] Confirm OpenBao audit logging is enabled.
- [ ] Confirm backups complete successfully.
- [ ] Confirm backup restore was tested.
- [ ] Confirm production and infra database credentials are separated.
- [ ] Confirm Woodpecker deployment permissions are scoped.
- [X] Confirm production images/versions are pinned where practical (status page tracks lag; 2026-10-12).
- [ ] Flesh out `update-containers.yml` (still a placeholder) or continue per-role `--tags` pull+up.
- [X] LiteLLM → `v1.105.0`; n8n → `2.42.7` (2026-10-12).
- [ ] Test controlled container update flow on a non-critical service.
- [ ] Document runbooks for restart, deploy, backup restore, certificate issue, and OpenBao recovery.

## Dependency Order Summary

1. Admin VPN and hardening.
2. WireGuard server-to-server network and firewall baseline.
3. VPS-2 Caddy/TLS/static site.
4. VPS-3 OpenBao/secrets.
5. VPS-1 Postgres and Valkey.
6. VPS-1 product backend services: Supabase, LiteLLM, Unleash.
7. VPS-3 infra services: Forgejo, Woodpecker, GlitchTip, n8n.
8. VPS-2 production apps: Parsr, CVForge, AIACC.
9. Monitoring, DLP, backup, and acceptance tests.
