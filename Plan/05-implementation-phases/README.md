# Implementation phase execution files

This folder expands `Plan/05-implementation-project-plan.md` into execution-focused phase files.

Use the root implementation plan as the dependency checklist. Use these files when actually performing a phase.

## Phase Files

| Phase | File |
|---:|---|
| 0 | `00-admin-vpn-and-hardening.md` |
| 1 | `01-network-and-firewall-baseline.md` **(done 2026-05-18)** |
| 1a | `01a-frontend-vps-docker-cleanup.md` (sub-plan, before Phase 1 Step 1.3) |
| 2 | `02-frontend-gateway-tls-static-site.md` **(done 2026-06-06)** |
| 3 | `03-openbao-and-secrets.md` |
| 4 | `04-backend-data-foundation.md` |
| 5 | `05-backend-product-services.md` |
| 6 | `06-infra-platform-services.md` |
| 7 | `07-production-apps.md` |
| 8 | `08-monitoring-dlp-operational-checks.md` |
| 9 | `09-final-hardening-and-acceptance.md` |

## Execution Rules

- Prefer Ansible for repeatable work.
- Keep provider-console, DNS, first SSH bootstrap, Tailscale enrollment, and OpenBao recovery steps manual.
- Do not store plaintext secrets in Git.
- Pin production container image versions where practical.
- Record deviations in the phase file before moving to the next phase.

