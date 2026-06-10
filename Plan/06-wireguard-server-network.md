# WireGuard server-to-server network

This plan configures the production server-to-server private network.

Admin access remains separate:

- **Tailscale**: laptop/admin access to VPS.
- **WireGuard**: VPS-to-VPS service traffic.

## Goal

Create an encrypted private network between the three VPS.

```text
VPS-1 Backend   10.44.0.1
VPS-2 Frontend  10.44.0.2
VPS-3 Infra     10.44.0.3
```

Service traffic uses WireGuard IPs:

```text
VPS-2 Caddy -> 10.44.0.1 -> Backend services
VPS-2 Caddy -> 10.44.0.3 -> Infra services
VPS-3 CI/n8n -> 10.44.0.1 / 10.44.0.2 -> deployment targets
```

## Address Plan

| Server | Public IP | WireGuard IP | UDP listen port |
|---|---:|---:|---:|
| VPS-1 Backend | `82.165.44.144` | `10.44.0.1/24` | `51820` |
| VPS-2 Frontend | `217.154.18.227` | `10.44.0.2/24` | `51820` |
| VPS-3 Infra | `82.165.34.239` | `10.44.0.3/24` | `51820` |

## Firewall Requirement

IONOS/cloud firewall and host firewall must allow:

| Server | Public UDP `51820` source |
|---|---|
| VPS-1 Backend | VPS-2 public IP, VPS-3 public IP |
| VPS-2 Frontend | VPS-1 public IP, VPS-3 public IP |
| VPS-3 Infra | VPS-1 public IP, VPS-2 public IP |

Do not open UDP `51820` to the whole internet if IONOS firewall supports source restrictions.

## Install WireGuard

On each VPS:

```bash
apt update
apt install -y wireguard
```

If the VPS image is not Debian/Ubuntu, use the distribution package manager equivalent.

## Generate Keys

On each VPS:

```bash
umask 077
wg genkey | tee /etc/wireguard/private.key | wg pubkey > /etc/wireguard/public.key
```

Show the public key:

```bash
cat /etc/wireguard/public.key
```

Collect the public keys:

```text
BACKEND_PUBLIC_KEY=<from VPS-1>
FRONTEND_PUBLIC_KEY=<from VPS-2>
INFRA_PUBLIC_KEY=<from VPS-3>
```

Never copy private keys between servers.

## VPS-1 Backend Config

Create `/etc/wireguard/wg0.conf` on VPS-1:

```ini
[Interface]
Address = 10.44.0.1/24
ListenPort = 51820
PrivateKey = BACKEND_PRIVATE_KEY

[Peer]
# VPS-2 Frontend
PublicKey = FRONTEND_PUBLIC_KEY
AllowedIPs = 10.44.0.2/32
Endpoint = 217.154.18.227:51820
PersistentKeepalive = 25

[Peer]
# VPS-3 Infra
PublicKey = INFRA_PUBLIC_KEY
AllowedIPs = 10.44.0.3/32
Endpoint = 82.165.34.239:51820
PersistentKeepalive = 25
```

## VPS-2 Frontend Config

Create `/etc/wireguard/wg0.conf` on VPS-2:

```ini
[Interface]
Address = 10.44.0.2/24
ListenPort = 51820
PrivateKey = FRONTEND_PRIVATE_KEY

[Peer]
# VPS-1 Backend
PublicKey = BACKEND_PUBLIC_KEY
AllowedIPs = 10.44.0.1/32
Endpoint = 82.165.44.144:51820
PersistentKeepalive = 25

[Peer]
# VPS-3 Infra
PublicKey = INFRA_PUBLIC_KEY
AllowedIPs = 10.44.0.3/32
Endpoint = 82.165.34.239:51820
PersistentKeepalive = 25
```

## VPS-3 Infra Config

Create `/etc/wireguard/wg0.conf` on VPS-3:

```ini
[Interface]
Address = 10.44.0.3/24
ListenPort = 51820
PrivateKey = INFRA_PRIVATE_KEY

[Peer]
# VPS-1 Backend
PublicKey = BACKEND_PUBLIC_KEY
AllowedIPs = 10.44.0.1/32
Endpoint = 82.165.44.144:51820
PersistentKeepalive = 25

[Peer]
# VPS-2 Frontend
PublicKey = FRONTEND_PUBLIC_KEY
AllowedIPs = 10.44.0.2/32
Endpoint = 217.154.18.227:51820
PersistentKeepalive = 25
```

## Enable WireGuard

On each VPS:

```bash
systemctl enable --now wg-quick@wg0
wg show
ip addr show wg0
```

## Test Connectivity

From VPS-1:

```bash
ping -c 3 10.44.0.2
ping -c 3 10.44.0.3
```

From VPS-2:

```bash
ping -c 3 10.44.0.1
ping -c 3 10.44.0.3
```

From VPS-3:

```bash
ping -c 3 10.44.0.1
ping -c 3 10.44.0.2
```

## Service Binding Rules

Backend services on VPS-1 should bind to `10.44.0.1` or localhost.

Infra services on VPS-3 should bind to `10.44.0.3` or localhost.

Frontend Caddy upstreams should use WireGuard IPs:

```text
supabase.ittd.app -> 10.44.0.1:<supabase-port>
proxy.ittd.app    -> 10.44.0.1:4000
flags.ittd.app    -> 10.44.0.1:<unleash-port>
secrets.ittd.app  -> 10.44.0.3:<openbao-port>
git.ittd.app      -> 10.44.0.3:<forgejo-port>
ci.ittd.app       -> 10.44.0.3:<woodpecker-port>
monitor.ittd.app  -> 10.44.0.3:<glitchtip-port>
automate.ittd.app -> 10.44.0.3:<n8n-port>
```

## Host Firewall Rules

Use WireGuard IPs in firewall allow rules.

VPS-1 Backend:

- Allow backend service ports from `10.44.0.2`.
- Allow deployment/automation ports from `10.44.0.3` only where required.
- Allow database ports only from approved WireGuard IPs.
- Allow Valkey only from approved WireGuard IPs.

VPS-2 Frontend:

- Allow public `80/tcp` and `443/tcp`.
- Allow WireGuard `51820/udp` from VPS-1 and VPS-3 public IPs.
- Keep app ports private behind Caddy.

VPS-3 Infra:

- Allow infra tool ports from `10.44.0.2`.
- Allow deployment access to targets only where required.
- Keep OpenBao, Forgejo, Woodpecker, GlitchTip, and n8n off public interfaces.

## Acceptance Criteria

- `wg show` shows recent handshakes between all peers.
- Each VPS can ping the other two WireGuard IPs.
- VPS-2 Caddy can reach VPS-1 services over `10.44.0.1`.
- VPS-2 Caddy can reach VPS-3 services over `10.44.0.3`.
- Public scans do not show backend, infra, database, or Valkey ports.
- Service configs and Caddy upstreams use WireGuard IPs, not public IPs.

