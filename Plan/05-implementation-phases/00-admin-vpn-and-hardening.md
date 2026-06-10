# Phase 0: Admin VPN And VPS Hardening

Goal: establish reliable admin access and a hardened baseline before closing public SSH.

Primary references:

- `Plan/00-fedora-tooling.md`
- `Plan/01-ansible-intro.md`
- `Plan/04-admin-vpn-step-zero.md`
- `Plan/IONOS Servers.md`

## Operating Rules

- Do not disable public SSH until Tailscale SSH, normal SSH, Ansible access, and IONOS console recovery are all confirmed.
- Keep one existing SSH session open while changing SSH settings.
- Use manual steps only for console access, initial SSH, Tailscale enrollment, and final verification.
- Use Ansible for repeatable hardening once basic access is proven.
- Record every final hostname, VPN IP, username, and SSH alias in this file before moving to Phase 1.

## Target Result

By the end of this phase:

- The Fedora workstation can reach all three VPS over Tailscale.
- Each VPS has a clear Tailscale node name.
- Ansible can connect to all VPS through the intended admin path.
- A non-root admin user exists on all VPS.
- Password SSH is disabled.
- Direct root SSH is disabled only after admin access is proven.
- Baseline packages, logging, time sync, and SSH protection are installed.
- Public SSH remains open only as long as needed for emergency access.

## Step 0.1: Confirm IONOS Console Access

Status: **Completed**

Purpose: make sure you have a recovery path if SSH configuration breaks.

1. Log in to the IONOS Cloud/Server panel.
2. Open each VPS page:

```text
VPS-1 Backend   82.165.44.144
VPS-2 Frontend  217.154.18.227
VPS-3 Infra     82.165.34.239
```

3. Confirm you can access the web console or recovery console for each VPS.
4. Confirm you can restart each VPS from the provider panel.
5. Confirm you know where provider firewall rules are configured.

Acceptance:

- [X] You can open a console session for all three VPS.
- [X] You can identify the firewall screen for all three VPS.

Completion note: IONOS console access, restart access, and firewall location are confirmed for all three VPS.

## Step 0.2: Confirm Existing SSH Access

Status: **Completed**

Purpose: prove current access before changing anything.

From Fedora:

```bash
ssh ionos-backend 'hostname && whoami && uptime'
ssh ionos-frontend 'hostname && whoami && uptime'
ssh ionos-infra 'hostname && whoami && uptime'
```

If SSH aliases are not installed yet, use public IPs:

```bash
ssh root@82.165.44.144 'hostname && whoami && uptime'
ssh root@217.154.18.227 'hostname && whoami && uptime'
ssh root@82.165.34.239 'hostname && whoami && uptime'
```

Acceptance:

- [X] Each server returns its hostname.
- [X] Each server shows the expected user, currently likely `root`.
- [X] No SSH key or host key issue is blocking access.

Completion note: SSH from the Fedora fish shell works with the configured SSH key/certificate. Passphrase prompts are expected when the private key is encrypted and no SSH agent has cached the unlocked key.

## Step 0.3: Install Tailscale On Fedora

Purpose: create the admin VPN entry point from the workstation.

On Fedora:

```bash
sudo dnf install -y tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Follow the browser login prompt.

Check status:

```bash
tailscale status
tailscale ip -4
```

Acceptance:

- [X] Fedora appears in the Tailscale admin console.
- [X] `tailscale ip -4` returns a `100.x.y.z` address.

Recommended node name:

```text
rog-fedora
```

Completion note: Fedora workstation `rog-fedora` is connected to Tailscale with IP `100.118.29.96`.

## Step 0.4: Install Tailscale On Each VPS

Status: **Completed**

Purpose: put each VPS on the admin VPN.

Run the appropriate install command for the VPS distribution.

For Debian/Ubuntu-based VPS images:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
tailscale up
```

For Fedora/RHEL-based VPS images:

```bash
dnf install -y tailscale
systemctl enable --now tailscaled
tailscale up
```

Run this on each VPS:

```text
VPS-1 Backend
VPS-2 Frontend
VPS-3 Infra
```

Recommended Tailscale node names:

```text
ts-ionos-backend
ts-ionos-frontend
ts-ionos-infra
```

Check from each VPS:

```bash
tailscale status
tailscale ip -4
```

Acceptance:

- [X] All three VPS appear in the Tailscale admin console.
- [X] Each VPS has a stable Tailscale IP.
- [X] Fedora can see all three VPS in `tailscale status`.

Completion note: Tailscale installation and enrollment are confirmed on all three VPS.

## Step 0.5: Test SSH Over Tailscale

Purpose: verify SSH works through the VPN before tightening public access.

Current Tailscale nodes:

```text
Fedora workstation  rog-fedora          100.118.29.96
VPS-1 Backend       ts-ionos-backend    100.89.8.19
VPS-2 Frontend      ts-ionos-frontend   100.118.224.43
VPS-3 Infra         ts-ionos-infra      100.108.51.103
```

From Fedora, confirm Tailscale status:

```bash
tailscale status
tailscale ip -4
```

Then test SSH to each VPS Tailscale IP:

```bash
ssh root@100.89.8.19 'hostname && ip -brief addr'
ssh root@100.118.224.43 'hostname && ip -brief addr'
ssh root@100.108.51.103 'hostname && ip -brief addr'
```

If MagicDNS is enabled in Tailscale, also test names:

```bash
ssh -i ~/.ssh/id_ed25519_ionos_aihub root@ts-ionos-backend 'hostname'
ssh -i ~/.ssh/id_ed25519_ionos_aihub root@ts-ionos-frontend 'hostname'
ssh -i ~/.ssh/id_ed25519_ionos_aihub root@ts-ionos-infra 'hostname'
```

Important: direct commands such as `ssh root@ts-ionos-backend` do not use the `Host ionos-backend` config block. Either use `ssh ionos-backend` after Step 0.6, add matching `Host ts-ionos-*` entries, or pass `-i ~/.ssh/id_ed25519_ionos_aihub`.

Acceptance:

- [X] SSH works to each VPS over its Tailscale address or MagicDNS name.
- [X] Public-IP SSH remained available during bootstrap, then root/password SSH was later disabled in Step 0.11.

Completion note: SSH over Tailscale/MagicDNS is confirmed. Normal access is now `admin@ts-ionos-*`.

## Step 0.6: Update Local SSH Config

Status: **Completed**

Purpose: keep both Tailscale admin access and temporary direct public-IP backup access.

Edit `~/.ssh/config` on Fedora.

Current chosen temporary form while still using `root`:

```sshconfig
Host ts-ionos-backend
  HostName ts-ionos-backend
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub

Host ts-ionos-frontend
  HostName ts-ionos-frontend
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub

Host ts-ionos-infra
  HostName ts-ionos-infra
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub

Host ionos-backend
  HostName 82.165.44.144
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub

Host ionos-frontend
  HostName 217.154.18.227
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub

Host ionos-infra
  HostName 82.165.34.239
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub
```

Meaning:

- `ts-ionos-*` aliases use Tailscale/MagicDNS and are the normal admin path.
- `ionos-*` aliases use public IPs and remain temporary backup access at this stage.
- Ansible should use the `ts-ionos-*` aliases once Step 0.7 is updated.

Test:

```bash
ssh ts-ionos-backend 'hostname'
ssh ts-ionos-frontend 'hostname'
ssh ts-ionos-infra 'hostname'
ssh ionos-backend 'hostname'
ssh ionos-frontend 'hostname'
ssh ionos-infra 'hostname'
```

Acceptance:

- [X] The `ts-ionos-*` aliases connect through Tailscale.
- [X] The `ionos-*` aliases connect through public IPs as temporary backup access.
- [X] All aliases use `~/.ssh/id_ed25519_ionos_aihub`.

Completion note: Local SSH config is confirmed with Tailscale aliases for normal admin access and public-IP aliases retained as temporary backup access.

## Step 0.7: Prepare Ansible Inventory

Status: **Completed**

Purpose: point Ansible at the same SSH aliases.

Confirm `ansible/inventory/hosts.yml` contains:

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

Confirm `ansible/ansible.cfg` contains:

```ini
[defaults]
inventory = inventory/hosts.yml
roles_path = roles
interpreter_python = auto_silent
remote_user = root
host_key_checking = False
retry_files_enabled = False
```

Then test:

```bash
cd ansible
ansible all -m ping
ansible all -m command -a "hostname"
```

Acceptance:

- [X] All three hosts return `pong`.
- [X] Hostnames match the expected VPS roles.

Completion note: `ansible all -m ping` succeeds for `ts-ionos-backend`, `ts-ionos-frontend`, and `ts-ionos-infra` over the Tailscale aliases.

## Step 0.8: Define The Non-Root Admin User

Status: **Completed**

Purpose: stop using `root` for normal administration.

Choose one admin username and use it consistently.

Recommended:

```text
admin
```

Record the final choice:

```text
Admin user: admin
SSH public key: ~/.ssh/id_ed25519_ionos_aihub.pub
```

The Ansible hardening role should create this user on all VPS with:

- Home directory.
- Sudo access.
- SSH authorized key.
- No password login requirement for SSH.

The current Ansible variables live in `ansible/inventory/group_vars/all.yml`:

```yaml
admin_user: admin
admin_ssh_public_key_file: "{{ lookup('env', 'HOME') }}/.ssh/id_ed25519_ionos_aihub.pub"
admin_sudo_group: sudo
```

Execute Step 0.8 with:

```bash
cd ansible
ansible-playbook playbooks/hardening.yml
```

This creates `admin`, installs the SSH public key, and grants passwordless sudo. It does not disable root SSH or password SSH yet.

Manual fallback command if Ansible is not ready:

```bash
adduser admin
usermod -aG sudo admin
install -d -m 700 -o admin -g admin /home/admin/.ssh
cp /root/.ssh/authorized_keys /home/admin/.ssh/authorized_keys
chown admin:admin /home/admin/.ssh/authorized_keys
chmod 600 /home/admin/.ssh/authorized_keys
```

Acceptance:

- [X] `admin` exists on all three VPS.
- [X] `admin` can use `sudo`.
- [X] `admin` can log in with SSH keys.

Completion note: `ansible-playbook playbooks/hardening.yml` created `admin`, installed the SSH public key, and granted passwordless sudo on all three VPS. Direct SSH login as `admin` over the Tailscale aliases is confirmed.

## Step 0.9: Build The First Hardening Playbook

Status: **Completed**

Purpose: make the baseline repeatable.

Use:

```bash
cd ansible
ansible-playbook playbooks/hardening.yml
```

The first implementation of `roles/base/tasks/main.yml` should manage:

- Package cache update.
- Baseline packages.
- Time sync.
- Persistent system logs.
- Automatic security updates.

The first implementation of `roles/ssh/tasks/main.yml` should manage:

- Admin user.
- Admin SSH key.
- Sudo access.
- SSH daemon settings.

Keep destructive SSH changes disabled until Step 0.11.

Current state:

- `playbooks/hardening.yml` exists and targets the `ionos` Ansible group.
- The playbook runs over the `ts-ionos-*` Tailscale aliases.
- The `ssh` role creates the `admin` user, installs the selected public key, and grants sudo.
- The `base` role is still a placeholder; baseline package installation starts in Step 0.10.
- The playbook does not disable password SSH or direct root SSH yet.

Optional: reduce SSH passphrase prompts with `ssh-agent`.

For fish shell:

```fish
eval (ssh-agent -c)
ssh-add ~/.ssh/id_ed25519_ionos_aihub
ssh-add -l
```

After that, repeated SSH and Ansible commands in the same session should reuse the unlocked key instead of asking for the passphrase every time. Keep the key passphrase; do not remove it from the private key.

Acceptance:

- [X] The playbook is repeatable.
- [X] Running it twice does not create unexpected changes for completed SSH tasks.
- [X] The playbook does not close your active SSH session.

Completion note: `playbooks/hardening.yml` has run successfully against all three VPS. Step 0.10 will replace the `base` placeholder with actual package, time sync, logging, and update tasks.

## Step 0.10: Install Baseline Packages

Status: **Completed**

Purpose: install the minimum operational tooling on all VPS.

The `base` role installs:

```text
apt-listchanges
apt-transport-https
ca-certificates
curl
fail2ban or equivalent
git
gnupg
htop
jq
lsb-release
nftables
python3-apt
rsync
systemd-timesyncd
unattended-upgrades
unzip
ufw
vim
```

It also configures:

- Persistent journald storage in `/var/log/journal`.
- A journald drop-in at `/etc/systemd/journald.conf.d/10-persistent.conf`.
- System time sync through `systemd-timesyncd`.
- Unattended apt security updates through `/etc/apt/apt.conf.d/20auto-upgrades`.
- `apt-daily.timer` and `apt-daily-upgrade.timer`.
- `fail2ban` installed, enabled, and running.

Execute Step 0.10 with:

```bash
cd ansible
ansible-playbook playbooks/hardening.yml
```

This does not configure restrictive firewall rules and does not disable root SSH. Those remain later steps.

Validation commands:

```bash
ansible all -m command -a "date"
ansible all -m command -a "systemctl is-active systemd-timesyncd" --ignore-errors
ansible all -m command -a "systemctl is-active chronyd" --ignore-errors
```

Acceptance:

- [X] Time sync is active through either `systemd-timesyncd` or `chrony`.
- [X] Common tooling is installed.

Completion note: `ansible-playbook playbooks/hardening.yml` installed the baseline packages, configured persistent journald, enabled `systemd-timesyncd`, enabled unattended apt updates, enabled apt daily timers, and started `fail2ban` on all three VPS.

## Step 0.11: Harden SSH In A Safe Order

Status: **Completed**

Purpose: disable unsafe SSH paths only after admin access is proven.

Required order:

1. Confirm `admin` SSH works over Tailscale.
2. Confirm `admin` can run `sudo`.
3. Update Ansible to connect as `admin`.
4. Confirm Ansible can become `root` with sudo.
5. Keep one `root` SSH session open as temporary backup.
6. Apply SSH daemon hardening through Ansible.
7. Test a new `admin` SSH session.
8. Confirm password login is rejected.
9. Confirm direct root SSH is rejected.

Test admin access:

```bash
ssh admin@ts-ionos-backend 'sudo -n true && hostname'
ssh admin@ts-ionos-frontend 'sudo -n true && hostname'
ssh admin@ts-ionos-infra 'sudo -n true && hostname'
```

Expected SSH daemon settings:

```text
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
```

Current Ansible settings:

```yaml
ansible_user: admin
ssh_hardening_enabled: true
```

The `ssh` role writes `/etc/ssh/sshd_config.d/90-cvforge-hardening.conf`:

```text
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
```

The handler validates with `/usr/sbin/sshd -t` before reloading `ssh`.

Execute:

```bash
cd ansible
ansible all -m ping
ansible all -b -m command -a "whoami"
ansible-playbook playbooks/hardening.yml
```

Important: keep one existing `root` SSH session open while running this. Do not close it until new `admin` sessions are tested.

Acceptance:

- [X] New admin SSH sessions work.
- [X] Password login is rejected.
- [X] Direct root login is rejected.
- [X] Existing emergency console access still works.

Completion note: `ansible-playbook playbooks/hardening.yml` applied the SSH hardening drop-in on all three VPS, validated `sshd` configuration, and reloaded SSH. New `admin` sessions over Tailscale work on all three VPS. Backend briefly refused SSH because fail2ban blocked the Fedora Tailscale IP after root-login rejection tests; unbanning restored access.

## Step 0.12: Update SSH Config To Use The Admin User

Status: **Completed**

Purpose: make normal operations non-root.

Update `~/.ssh/config`:

```sshconfig
Host ts-ionos-backend
  HostName ts-ionos-backend
  User admin
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub

Host ts-ionos-frontend
  HostName ts-ionos-frontend
  User admin
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub

Host ts-ionos-infra
  HostName ts-ionos-infra
  User admin
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub
```

Update `ansible/ansible.cfg`:

```ini
remote_user = admin
```

Test:

```bash
cd ansible
ansible all -m ping
ansible all -m command -a "whoami"
ansible all -b -m command -a "whoami"
```

Acceptance:

- [X] Normal Ansible user is `admin`.
- [X] Privileged Ansible command returns `root` when using `-b`.

Completion note: Normal SSH, Remmina, and Ansible access now use `admin`. Privileged automation uses sudo/become instead of root SSH.

## Step 0.13: Enable SSH Protection

Status: **Completed**

Purpose: reduce brute-force risk while public SSH is still available or partly available.

Use the selected protection tool, usually `fail2ban` for day one.

The Ansible role should manage:

- `fail2ban` package installation.
- SSH jail enabled.
- Conservative ban time.
- Systemd log backend for Ubuntu.
- Fedora workstation Tailscale IP ignored to prevent accidental self-ban.

Current fail2ban variables:

```yaml
fail2ban_ignore_ips:
  - 127.0.0.1/8
  - ::1
  - 100.118.29.96
fail2ban_findtime: 10m
fail2ban_bantime: 15m
fail2ban_maxretry: 5
```

Execute:

```bash
cd ansible
ansible-playbook playbooks/hardening.yml
```

Validation:

```bash
ansible all -b -m command -a "systemctl is-active fail2ban"
ansible all -b -m command -a "fail2ban-client status sshd"
```

Acceptance:

- [X] SSH protection service is active on all VPS.
- [X] SSH jail is enabled if using fail2ban.

Completion note: `fail2ban` is active on all three VPS and the `sshd` jail is enabled. Validation showed active bans from public SSH probes on Backend, Frontend, and Infra, confirming the protection is working.

## Step 0.14: Keep Public SSH Temporarily Controlled

Status: **Completed**

Purpose: avoid locking yourself out before Phase 1 firewall work is complete.

At this point:

- Tailscale SSH should be the normal admin path.
- Public SSH may remain temporarily available as emergency fallback.
- Do not rely on dynamic home IP allowlisting.
- Do not close SSH at IONOS firewall until console recovery and VPN access are proven.
- The fail2ban ignore list contains the Fedora Tailscale IP `100.118.29.96`, not the home/ISP IP.

Recommended temporary policy:

```text
Public SSH: temporarily open or provider-restricted if possible
Normal SSH: Tailscale only
Final SSH policy: decided in Phase 1 firewall baseline
```

Acceptance:

- [X] You know which path is normal admin access.
- [X] You know which path is emergency access.
- [X] You know how to recover if SSH config breaks.

Completion note: Normal admin access is `admin@ts-ionos-*` over Tailscale. Public SSH remains temporarily reachable until Phase 1 firewall rules, but password login and direct root SSH are disabled.

## Step 0.15: Final Phase Validation

Status: **Completed**

Run all checks before moving to Phase 1.

From Fedora:

```bash
ssh ts-ionos-backend 'hostname && whoami'
ssh ts-ionos-frontend 'hostname && whoami'
ssh ts-ionos-infra 'hostname && whoami'
```

From `ansible/`:

```bash
ansible all -m ping
ansible all -m command -a "hostname"
ansible all -b -m command -a "whoami"
ansible all -b -m command -a "timedatectl status"
```

Provider console:

- Open console for VPS-1.
- Open console for VPS-2.
- Open console for VPS-3.

Acceptance:

- [X] SSH works to all three VPS over Tailscale.
- [X] Ansible works against all three VPS.
- [X] Privilege escalation works through Ansible.
- [X] Console break-glass access is confirmed.
- [X] Password SSH is disabled.
- [X] Direct root SSH is disabled.
- [X] Public SSH is not closed until Phase 1 firewall rules are ready.

Completion note: Final validation confirmed SSH over Tailscale as `admin`, Ansible connectivity, Ansible privilege escalation to `root`, active NTP sync, and provider console break-glass access.

## Phase 0 Completion Record

Fill this in when the phase is complete.

```text
Admin user: admin
Fedora Tailscale IP: 100.118.29.96
Backend Tailscale IP: 100.89.8.19
Frontend Tailscale IP: 100.118.224.43
Infra Tailscale IP: 100.108.51.103
Backend SSH alias: ts-ionos-backend
Frontend SSH alias: ts-ionos-frontend
Infra SSH alias: ts-ionos-infra
SSH key used: ~/.ssh/id_ed25519_ionos_aihub
Tailscale MagicDNS enabled: yes
Public SSH still open: yes, temporarily until Phase 1 firewall rules
Provider console tested: yes
Date completed: 2026-05-10
```
