# Step 0: admin VPN access

This is the first VPS hardening step. It solves the problem that a home internet connection usually has a changing public IP, so SSH cannot safely rely on static admin IP allowlisting.

## Goal

Create a private admin network between the workstation and all three VPS.

```text
Fedora workstation -> admin VPN -> VPS-1 / VPS-2 / VPS-3
```

Normal laptop internet traffic remains outside the VPN. Only traffic to VPN IPs uses the VPN.

## Decision

Use split-tunnel VPN access for administration.

Recommended day-one option:

```text
Tailscale
```

Reason:

- Fast to set up.
- Works with changing home IPs.
- Split tunnel by default.
- Supports Linux servers and Fedora workstation.
- Reduces SSH lockout risk during first hardening.

Longer-term self-hosted option:

```text
Headscale + Tailscale clients
```

Manual option:

```text
WireGuard
```

Use WireGuard directly if you want no external coordination service, but expect more manual key and peer management.

## Traffic Model

Do not enable an exit node for this use case.

```text
Normal web/gaming/download traffic -> home ISP
SSH/admin traffic to VPS VPN IPs -> admin VPN
```

Example:

```text
cvforge.ittd.app       -> public internet -> VPS-2 Caddy
ssh root@100.x.y.z     -> Tailscale VPN -> selected VPS
```

## Target Access Policy

After VPN access is verified:

- SSH is allowed over the admin VPN.
- Public SSH is disabled or heavily restricted.
- Admin web UIs are VPN-only where practical.
- IONOS console remains the break-glass path.

## Setup: Tailscale Day One

### 1. Install on Fedora workstation

```bash
sudo dnf install tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Confirm:

```bash
tailscale status
```

### 2. Install on each VPS

Run on each server:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
tailscale up
```

Authenticate each VPS in the browser flow.

### 3. Name the nodes

Use clear node names in the Tailscale admin UI:

| Server | Suggested Tailscale name |
|---|---|
| VPS-1 Backend | `ionos-backend` |
| VPS-2 Frontend | `ionos-frontend` |
| VPS-3 Infra | `ionos-infra` |
| Fedora workstation | `fedora-workstation` |

### 4. Test VPN SSH

From Fedora:

```bash
tailscale status
ssh root@<backend-tailscale-ip> "hostname"
ssh root@<frontend-tailscale-ip> "hostname"
ssh root@<infra-tailscale-ip> "hostname"
```

Do not close existing public SSH sessions until this works.

## SSH Config

Add VPN-only aliases later:

```sshconfig
Host ionos-backend-vpn
  HostName <backend-tailscale-ip>
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub
  IdentitiesOnly yes

Host ionos-frontend-vpn
  HostName <frontend-tailscale-ip>
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub
  IdentitiesOnly yes

Host ionos-infra-vpn
  HostName <infra-tailscale-ip>
  User root
  IdentityFile ~/.ssh/id_ed25519_ionos_aihub
  IdentitiesOnly yes
```

After this, Ansible can use VPN aliases.

## Firewall Transition

Initial state:

- Public SSH remains open while VPN is being installed.
- Key-based SSH must work.
- IONOS console access must be available.

Target state:

- Public SSH closed, or temporarily limited as emergency fallback.
- SSH allowed on the Tailscale interface.
- VPS-2 keeps public `80/443`.
- VPS-1 and VPS-3 expose no public service ports.

Do not disable public SSH until:

1. VPN SSH works to all three VPS.
2. SSH keys work over VPN.
3. You have IONOS console access confirmed.
4. At least one active root/admin session remains open during the firewall change.

## OpenBao Admin Access

OpenBao lives on VPS-3.

Admin access policy:

- OpenBao human admin access requires MFA.
- Prefer `secrets.ittd.app` as VPN-only or IP/VPN-restricted through Caddy.
- Use OIDC with MFA if available.
- If no identity provider is available, use OpenBao login MFA with TOTP.

## Acceptance Criteria

- Fedora can SSH to all three VPS over VPN.
- Normal Fedora internet traffic still works without using a VPN exit node.
- Public apps still resolve through normal DNS.
- Public SSH can be disabled without losing access.
- The network/firewall policy can use VPN IPs instead of home public IPs.

