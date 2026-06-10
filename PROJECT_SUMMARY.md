## Summary

This repository defines the **CVForge** infrastructure running on **3 IONOS VPS (Linux L)**, managed from a **Fedora KDE** workstation. The goal is a secure, repeatable, documented setup for hosting the CVForge production application plus the company platform services needed to build and operate it.

## Intended server roles

- **VPS-1 (Backend)**: CVForge supporting backend services such as Supabase, LiteLLM, Unleash, production Postgres, infra Postgres, and Valkey.
- **VPS-2 (Frontend)**: public Caddy/TLS gateway plus production apps: CVForge, Parsr, and AIACC.
- **VPS-3 (Infra/DevOps)**: company platform services such as OpenBao secrets, Forgejo source control, Woodpecker CI/CD, GlitchTip monitoring/error tracking, n8n automation, and runbooks.

## High-level implementation phases

- **Planning & documentation**: keep executable plans and runbooks in `Plan/`.
- **Phase execution notes**: use `Plan/05-implementation-phases/` for detailed execution notes per project phase.
- **Service layout**: split the old single-VPS stack into CVForge production Backend/Frontend plus company Infra/DevOps responsibilities.
- **Fedora workstation tooling**: ensure SSH, key management, automation tools, and consistent CLI UX.
- **Ansible infrastructure as code**: use Ansible from the Fedora workstation for repeatable VPS setup, Docker/Compose deployment, firewall rules, WireGuard, and controlled updates.
- **Admin VPN step zero**: establish split-tunnel VPN admin access before locking down public SSH.
- **VPS hardening**: secure baseline on all three servers (users, SSH, firewall, updates, audit).
- **Certificates & TLS**: obtain/manage certificates for public endpoints.
- **Network/firewall policy**: enforce VPS-2 as the only public HTTP/HTTPS gateway and keep backend/infra service ports private.
- **Server-to-server WireGuard**: use a VPS-only WireGuard mesh for production service traffic.
- **Container platform**: install Docker, compose tooling, and standard service layout.
- **Reverse proxy / "reverse NAT"**: configure a reverse proxy layer (routing, TLS termination, access control) so services can be exposed safely.
- **Service deployment**: bring up backend, frontend, and infra stacks with backups and monitoring.

## Repo conventions (proposed)

- **Plans** live in `Plan/` and are written to be followed step-by-step.
- **Idempotence**: prefer automation and commands that can be re-run safely.
- **Secrets**: never commit secrets; use `.env` files locally and server-side secret storage.

## Next file to execute

Start with `Plan/00-fedora-tooling.md`, then `Plan/01-ansible-intro.md`, then execute `Plan/05-implementation-project-plan.md`. Complete `Plan/04-admin-vpn-step-zero.md` before locking down SSH, and use `Plan/02-three-server-service-layout.md`, `Plan/03-network-firewall-policy.md`, and `Plan/06-wireguard-server-network.md` as the target architecture and network policy.
