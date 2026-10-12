# Ansible quick intro (IONOS AI Hub)

## What Ansible is

**Ansible** runs tasks on remote machines over **SSH** from your workstation (the **control node**). You describe **what** should be true (packages installed, files present, services running) in **playbooks** (YAML); Ansible uses **modules** to make the remote system match that description. It is **agentless**: nothing permanent is required on the VPS beyond Python (usually already there) and SSH access.

Useful mental model:

- **Inventory** — which hosts exist and how they are grouped (e.g. `backend`, `frontend`, `infra`).
- **Playbook** — ordered steps against one or more groups.
- **Role** — reusable bundle of tasks, variables, and templates (optional; add when playbooks grow).

Official docs: [https://docs.ansible.com/](https://docs.ansible.com/)

## How this fits your project

- **Control node:** your Fedora machine (where you run `ansible-playbook` / `ansible`).
- **Managed nodes:** the three IONOS VPS from `Plan/IONOS Servers.md`.
- **Transport:** Tailscale SSH aliases from `~/.ssh/config`. Ansible uses `ts-ionos-backend`, `ts-ionos-frontend`, and `ts-ionos-infra`. Public-IP aliases `ionos-backend`, `ionos-frontend`, and `ionos-infra` remain manual backup access during bootstrap.

Ansible is the infrastructure-as-code layer for this project.

Use it for repeatable operations:

- VPS hardening.
- Users, SSH config, packages, logs, and update settings.
- WireGuard server-to-server configuration.
- Host firewall configuration.
- Docker and Docker Compose installation.
- Service directories, Compose files, and Caddy config.
- Controlled container updates when you decide to pull newer pinned images.

Keep these steps manual:

- IONOS console actions.
- First SSH/bootstrap access.
- Tailscale device login/enrollment.
- DNS record changes.
- OpenBao unseal/recovery handling.
- Emergency break-glass recovery.

## Working directory (required)

Always run Ansible from `ansible/` so `ansible.cfg` loads inventory and `roles_path`. From the repo root, hosts look empty and roles under `ansible/roles/` are not found.

```bash
cd ansible
ansible-playbook playbooks/gateway.yml
```

Boolean `set_fact` values must be one-line `"{{ expr }}"`. Folded scalars (`>-`) turn `True` into `"\nTrue"`, which `| bool` treats as false — that bug skipped LiteLLM secret restore during the 2026-10-12 upgrade (see Phase 5 LiteLLM lessons).

## Install (control node)

```bash
sudo dnf -y install ansible
ansible --version
```

## Suggested layout in this repo

Keep automation next to `Plan/` but out of secrets and large artifacts:

```text
ansible/
  ansible.cfg          # local defaults (inventory path, etc.)
  inventory/
    hosts.yml          # or hosts.ini — your three VPS + groups
    group_vars/        # all.yml, backend.yml, …
  host_vars/           # optional: per-host overrides
  playbooks/
    site.yml           # example entry playbook
  roles/               # optional: add when you split work by concern
```

This repository includes a ready-to-use tree under **`ansible/`** (`ansible.cfg`, `inventory/hosts.yml`, `inventory/group_vars/all.yml`, `playbooks/site.yml`, `roles/`).

## Minimal `ansible.cfg`

Create `ansible/ansible.cfg` so commands work from the `ansible/` directory (or set `ANSIBLE_CONFIG`):

```ini
[defaults]
inventory = inventory/hosts.yml
interpreter_python = auto_silent
remote_user = root
host_key_checking = False
retry_files_enabled = False
```

`host_key_checking = False` avoids prompts on first connect; once `known_hosts` is populated you can set this to `True` for stricter behavior.

## Minimal inventory (`inventory/hosts.yml`)

Host keys must match **`~/.ssh/config`** `Host` names so SSH resolves the right IP and key:

```yaml
all:
  children:
    ionos:
      hosts:
        ts-ionos-backend:
        ts-ionos-frontend:
        ts-ionos-infra:
    backend:
      hosts:
        ts-ionos-backend:
    frontend:
      hosts:
        ts-ionos-frontend:
    infra:
      hosts:
        ts-ionos-infra:
```

If you prefer not to rely on SSH config, set `ansible_host` per host to the Tailscale IP and keep `ansible_user: root` in `inventory/group_vars/all.yml` or under each host.

## First checks

From the directory that contains `ansible.cfg` (or with `ANSIBLE_CONFIG` pointing at it):

```bash
cd ansible
ansible all -m ping
ansible ionos -m command -a "uname -a"
```

You should get `pong` from each host and sensible `uname` output.

## Playbooks: start small

Example `playbooks/site.yml`:

```yaml
---
- name: Baseline check
  hosts: ionos
  gather_facts: true
  tasks:
    - name: Show OS
      ansible.builtin.debug:
        msg: "{{ ansible_distribution }} {{ ansible_distribution_version }}"
```

Run:

```bash
ansible-playbook playbooks/site.yml
```

## Secrets and variables

- Put non-secret defaults in **`group_vars/`** or **`host_vars/`** as plain YAML.
- For passwords, API tokens, or keys, use **`ansible-vault`** to encrypt files (e.g. `group_vars/all/vault.yml`) and pass `--ask-vault-pass` or a vault password file at runtime. Do not commit plaintext secrets; align with `Plan/00-fedora-tooling.md` (KeePass, no secrets in git).

## Next steps for IONOS

1. Run **`ping`** and a trivial playbook against **`ionos`**.
2. Add a **hardening** playbook (users, `sshd`, firewall, updates) and split into **roles** when it grows.
3. Add roles for WireGuard, Docker, Caddy, backend services, infra services, and production apps.
4. Add an `update-containers.yml` playbook for deliberate image pulls and restarts.

Cross-reference: server IPs and SSH aliases — `Plan/IONOS Servers.md`; workstation packages and SSH — `Plan/00-fedora-tooling.md`.
