# Phase 9: Final Hardening And Acceptance

Goal: prove the infrastructure is ready for production operation.

Primary references:

- `Plan/02-three-server-service-layout.md`
- `Plan/03-network-firewall-policy.md`
- `Plan/05-implementation-project-plan.md`

## Exposure Acceptance

Verify:

- Public internet can reach only VPS-2 `80/tcp` and `443/tcp`.
- VPS-1 service/database ports are not publicly reachable.
- VPS-3 tool ports are not publicly reachable.
- SSH works over VPN.
- Public SSH is disabled or heavily restricted.
- IONOS console break-glass access works.

## Application Acceptance

Verify:

- All required Caddy routes work.
- Admin domains require authentication and/or VPN/IP restriction.
- CVForge core flows work.
- AIACC core flow works.
- Backend and infra upstreams use WireGuard IPs.
- Parsr is private unless intentionally exposed.

## Security Acceptance

Verify:

- OpenBao MFA is enforced for human admins.
- OpenBao audit logging is enabled.
- Root token is not used for normal operation.
- Production and infra database credentials are separated.
- Woodpecker deployment permissions are scoped.
- Secrets are absent from logs, CI output, GlitchTip events, and n8n history.

## Operations Acceptance

Verify:

- Backups complete successfully.
- Backup restore was tested.
- GlitchTip alerts work.
- n8n alert flow works if enabled.
- Production images are pinned where practical.
- Controlled container update flow works on a non-critical service.

Run the future controlled update playbook:

```bash
cd ansible
ansible-playbook playbooks/update-containers.yml --limit <target>
```

## Required Runbooks

Create or link runbooks for:

- Restart service.
- Deploy service.
- Roll back service.
- Backup restore.
- Certificate issue.
- OpenBao recovery.
- Lost VPN/admin access.
- Database emergency.

## Notes And Decisions

Record final production acceptance results and remaining known risks here.

