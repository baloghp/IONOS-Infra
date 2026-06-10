## Goal

Prepare your **Fedora KDE** workstation to reliably manage and deploy the AI Hub infrastructure across 3 IONOS VPS. This plan focuses on: SSH hygiene, automation tooling, container tooling, and a consistent terminal workflow.

## Assumptions

- Fedora 44 (or similar) with `fish`
- You will manage VPS via SSH (start with password, migrate to keys as part of hardening)
- You’ll deploy services primarily via Docker/Compose

## 0) Update system and install baseline packages

```bash
sudo dnf -y upgrade
sudo dnf -y install \
  git curl wget jq yq \
  openssh-clients openssl \
  rsync unzip zip \
  htop btop tree \
  podman podman-compose \
  python3 python3-pip \
  remmina
```

Notes:
- Fedora ships Podman; we install it as a local container tool even if servers use Docker.
- We’ll add Docker CLI tooling later only if you need it locally.

## 1) SSH access via Remmina (primary)

Use **Remmina** for interactive shell sessions to the VPS. Create one **SSH** profile per host from `Plan/IONOS Servers.md` (IP, user `root`). Prefer storing passwords in **KeePass** and pasting when connecting, or use an SSH private key in the connection’s SSH options if you use key-based auth.

Optional: remove the `keychain` package if you installed it only for fish (`sudo dnf remove keychain`).

### 1.1 Optional: dedicated key for Remmina / `ssh` CLI

If you already have a key, reuse it. Otherwise:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -a 64 -f ~/.ssh/id_ed25519_ionos_aihub -C "ionos-aihub"
chmod 600 ~/.ssh/id_ed25519_ionos_aihub
chmod 644 ~/.ssh/id_ed25519_ionos_aihub.pub
```

In Remmina, point the connection at `~/.ssh/id_ed25519_ionos_aihub` (or your chosen path) where the UI asks for a private key.

## 2) Define SSH config for the three VPS (optional; useful for `ssh` / Ansible)

Server details live in `Plan/IONOS Servers.md`. Mapping:

| Role     | SSH alias       | Address        | User |
|----------|-----------------|----------------|------|
| Backend  | `ionos-backend` | 82.165.44.144  | root |
| Frontend | `ionos-frontend`| 217.154.18.227 | root |
| Infra    | `ionos-infra`   | 82.165.34.239  | root |

### 2.1 First login (password) and install your public key on each server

Create a key in **§1.1** (or use an existing one) if you want key-based login.

**A) One-time password SSH** — use the root password from the IONOS panel (or whatever you set at provision time). Accept the host key when prompted (`yes`).

```bash
ssh root@82.165.44.144
ssh root@217.154.18.227
ssh root@82.165.34.239
```

**B) Push your public key** — from your workstation, while password auth still works (Fedora: `openssh-clients` provides `ssh-copy-id`):

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_ionos_aihub.pub root@82.165.44.144
ssh-copy-id -i ~/.ssh/id_ed25519_ionos_aihub.pub root@217.154.18.227
ssh-copy-id -i ~/.ssh/id_ed25519_ionos_aihub.pub root@82.165.34.239
```

That creates/updates `~/.ssh/authorized_keys` on each host with the right permissions.

**C) Verify key login** (still using IP, before `~/.ssh/config`):

```bash
ssh -i ~/.ssh/id_ed25519_ionos_aihub -o IdentitiesOnly=yes root@82.165.44.144 "echo OK-backend"
ssh -i ~/.ssh/id_ed25519_ionos_aihub -o IdentitiesOnly=yes root@217.154.18.227 "echo OK-frontend"
ssh -i ~/.ssh/id_ed25519_ionos_aihub -o IdentitiesOnly=yes root@82.165.34.239 "echo OK-infra"
```

You should not be prompted for a password if SSH finds the key via `-i` (or your agent has the key loaded).

**Optional hardening later:** disable password authentication and root password login in `sshd_config` only after you confirm key access from your usual machine (separate hardening plan).

### 2.2 `~/.ssh/config` (exact copy)

Create/edit `~/.ssh/config` as **your user** (not `root`). If the file is owned by root, `ssh` will **ignore** it and names like `ionos-backend` are sent to DNS → `Could not resolve hostname`. Fix with `sudo chown "$USER:$USER" ~/.ssh/config`.

```sshconfig
Host ionos-backend
  HostName 82.165.44.144
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 3

Host ionos-frontend
  HostName 217.154.18.227
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 3

Host ionos-infra
  HostName 82.165.34.239
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

Lock permissions:

```bash
chmod 600 ~/.ssh/config
```

Test connectivity using aliases:

```bash
ssh ionos-backend "uname -a"
ssh ionos-frontend "uname -a"
ssh ionos-infra "uname -a"
```

After `config` exists, you can also add keys with aliases (same effect as IP):

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_ionos_aihub.pub ionos-backend
ssh-copy-id -i ~/.ssh/id_ed25519_ionos_aihub.pub ionos-frontend
ssh-copy-id -i ~/.ssh/id_ed25519_ionos_aihub.pub ionos-infra
```

## 3) Install infrastructure automation tooling

### Option A (recommended): Ansible

```bash
sudo dnf -y install ansible
ansible --version
```

Create an inventory later once VPS hardening work begins.

### Option B: Terraform/OpenTofu (optional)

If you plan to manage DNS/Cloud resources as code, install OpenTofu:

```bash
sudo dnf -y install tofu
tofu version
```

If `tofu` isn’t available in your repos, we’ll add it via official instructions later.

## 4) Local secrets workflow (do this early)

- Do **not** store secrets in the git repository.
- Use `.env` files locally but ensure they are always ignored (we’ll add `.gitignore` once the repo is initialized).
- Primary secret storage: keep secrets in **KeePass** databases stored separately from the codebase.
- Prefer per-environment copies (dev/stage/prod) and rotate secrets when a team member leaves.

## 5) Install and configure Git basics

```bash
git --version
```

If you haven’t configured your identity:

```bash
git config --global user.name "YOUR NAME"
git config --global user.email "you@example.com"
```

## 6) Quality-of-life terminal setup (optional but helpful)

- Ensure your terminal has a readable font and supports ligatures if you like.
- `starship` is already in use with fish (no action required).

## Exit criteria (Fedora tooling done)

- You can open an SSH session to each VPS via **Remmina** (and optionally via `ssh ionos-*` if you use `~/.ssh/config`).
- You have `git`, `jq`, `yq`, `ansible`, and `python3` installed.
- You have a repeatable place in this repo (`Plan/`) to track infra work.

## Next

Create a shared hardening baseline plan for all VPS (users, SSH, firewall, updates, fail2ban, unattended upgrades), then implement it with Ansible.
