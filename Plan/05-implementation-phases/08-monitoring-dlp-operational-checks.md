# Phase 8: Monitoring, DLP, And Operational Checks

Goal: verify the system is observable and sensitive data is protected in logs, events, and AI flows.

Primary references:

- `Plan/02-three-server-service-layout.md`
- `Plan/03-network-firewall-policy.md`

## Monitoring Scope

GlitchTip handles:

- Application exception tracking.
- Uptime checks.
- SSL expiry checks.
- Basic service health visibility.

n8n handles selected alert workflows.

## Checks To Configure

Public checks:

- `cvforge.ittd.app`
- `aiacc.ittd.app`
- `www.ittd.app`
- `git.ittd.app`
- `ci.ittd.app`
- `monitor.ittd.app`
- `automate.ittd.app`

Private or restricted checks:

- Supabase health.
- LiteLLM health.
- Unleash health.
- Production Postgres reachability.
- Infra Postgres reachability.
- Valkey reachability.

## DLP Work

Define and verify scrubbing for:

- API keys.
- Session tokens.
- Authorization headers.
- Passwords.
- CV and document content.
- AI prompts.
- AI responses where they may include user data.
- Request bodies.
- Database connection strings.

## Ansible Work

Use Ansible for repeatable operational configuration:

- GlitchTip service configuration.
- n8n service configuration.
- Alert webhook configuration where practical.
- Cron/systemd health scripts if needed.
- Backup check scripts.

## Validation

- A test exception from CVForge appears in GlitchTip.
- A test exception from AIACC appears in GlitchTip if instrumented.
- Uptime checks alert correctly.
- SSL expiry checks are active.
- n8n receives a test GlitchTip webhook.
- Sustained outage flow can create a Forgejo issue if enabled.
- Secrets do not appear in CI logs.
- Secrets do not appear in n8n logs.
- Secrets do not appear in GlitchTip events.
- AI prompt/document DLP rules are documented.

## Notes And Decisions

Record retention periods, alert destinations, escalation rules, and DLP exclusions here.

