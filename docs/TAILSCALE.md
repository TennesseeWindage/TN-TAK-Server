# Tailscale Integration

## Overview

[Tailscale](https://tailscale.com) is a WireGuard-based mesh VPN. It allows ATAK clients
at remote locations (coalition HQ, command post, remote squads) to reach TN-TAK-Server
securely over the internet or any data link without opening firewall ports.

```
     LightIFF Targeting Computer (RZ/V2H)
     ┌─────────────────────────────────────┐
     │  TN-TAK-Server + Tailscale daemon   │
     │  Tailscale IP: 100.x.y.z           │
     └─────────────────────────────────────┘
              │  WireGuard tunnel
     ─────────┼────────────────────────────
              │
     ┌────────┴────────────────────────────┐
     │  ATAK Clients (Tailscale installed)  │
     │  100.a.b.c → 100.x.y.z:8443         │
     └─────────────────────────────────────┘
```

---

## Setup

### 1. Generate Auth Key

1. Log in at [https://login.tailscale.com/admin/settings/keys](https://login.tailscale.com/admin/settings/keys)
2. Create a reusable (or one-time) auth key
3. Write to `config/tailscale/authkey` and `chmod 600 config/tailscale/authkey`

```bash
echo "tskey-auth-..." > config/tailscale/authkey
chmod 600 config/tailscale/authkey
```

### 2. Run Setup Script

```bash
chmod +x scripts/setup-tailscale.sh
./scripts/setup-tailscale.sh
```

The script:
- Installs Tailscale on the host (if not present)
- Authenticates with your tailnet using the auth key
- Reports the Tailscale IP (e.g., `100.x.y.z`)

### 3. Configure ACL

Paste `config/tailscale/acl-policy.jsonc` into [https://login.tailscale.com/admin/acls](https://login.tailscale.com/admin/acls).

This restricts TAK client devices (`tag:tak-client`) to reach only TAK ports on the
server (`tag:tak-server`), and allows admin SSH.

### 4. Connect ATAK Clients

On each ATAK Android device:

1. Install [Tailscale for Android](https://play.google.com/store/apps/details?id=com.tailscale.ipn)
2. Log in with your tailnet account
3. In ATAK → TAK Server settings:
   - Address: `100.x.y.z` (Tailscale IP of TAK Server)
   - Port: `8443`
   - SSL: enabled

---

## Self-Hosted Option (Headscale)

For air-gapped or classified networks, use [Headscale](https://github.com/juanfont/headscale)
as a self-hosted Tailscale coordination server:

```bash
# Install Headscale on a trusted server
# Configure clients to point to Headscale URL instead of Tailscale cloud
tailscale up --login-server https://headscale.yourdomain.com ...
```

---

## Notes

- Tailscale works over any data link: cellular, satellite, Starlink, Wi-Fi — the WireGuard tunnel
  handles NAT traversal automatically.
- Latency overhead: WireGuard is typically < 1 ms additional latency on LAN; several ms over
  internet — acceptable for CoT / LightIFF SA events.
- **Do not use Tailscale as the sole connectivity layer in EMCOM scenarios** — it requires an
  internet connection to the Tailscale coordination server for initial auth. Use Meshtastic or
  Netbird (self-hosted) as the fallback.
