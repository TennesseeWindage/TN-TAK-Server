# Netbird Integration

## Overview

[Netbird](https://netbird.io) is a zero-trust mesh VPN based on WireGuard with a
self-hostable management plane. It is a strong alternative to Tailscale for air-gapped,
classified, or enterprise deployments where you cannot depend on cloud coordination.

```
  ┌─────────────────────────────────────────────┐
  │  Netbird Management Plane                    │
  │  (cloud: api.netbird.io OR self-hosted)      │
  └──────────────────┬──────────────────────────┘
                     │  WireGuard signalling
         ┌───────────┴──────────────────┐
         │                              │
  ┌──────┴───────────┐         ┌────────┴──────────────┐
  │  RZ/V2H          │         │  ATAK Client Devices   │
  │  TN-TAK-Server   │◄────────┤  (Android, WinTAK)     │
  │  Netbird IP      │WireGuard│  Netbird IP            │
  └──────────────────┘         └───────────────────────┘
```

---

## Cloud vs Self-Hosted

| Option | Management plane | Best for |
|--------|-----------------|----------|
| Cloud (default) | `api.netbird.io` | Small teams, quick setup |
| Self-hosted (Netbird OSS) | Your own server | Air-gapped, classified, enterprise |

Self-hosted setup: [https://docs.netbird.io/selfhosted/selfhosted-quickstart](https://docs.netbird.io/selfhosted/selfhosted-quickstart)

---

## Setup

### 1. Create a Netbird Account / Self-Hosted Instance

- Cloud: [https://app.netbird.io](https://app.netbird.io)
- Self-hosted: Follow Netbird self-hosted quickstart

### 2. Generate a Setup Key

In the Netbird dashboard → Settings → Setup Keys → Create:

- Type: **Reusable** (for multiple TAK Server hosts) or **One-Time**
- Groups: Assign to `tak-servers` group

Write the key:

```bash
echo "YOUR_SETUP_KEY" > config/netbird/setup-key
chmod 600 config/netbird/setup-key
```

### 3. Configure Management URL (self-hosted only)

```bash
cp config/netbird/netbird.env.example config/netbird/netbird.env
# Edit NB_MANAGEMENT_URL=https://netbird.yourdomain.com
```

### 4. Run Setup Script

```bash
chmod +x scripts/setup-netbird.sh
./scripts/setup-netbird.sh
```

The script installs Netbird, starts the daemon, and connects to the management plane.

### 5. Configure Policies

In the Netbird dashboard → Policies, create rules per `config/netbird/policy-notes.md`:

- `tak-clients` → `tak-servers`: TCP ports 8443, 8444, 8446
- `admins` → `tak-servers`: all (SSH + web UI)

### 6. Connect ATAK Clients

On each ATAK Android device:

1. Install [Netbird for Android](https://play.google.com/store/apps/details?id=io.netbird.client)
2. Log in with your Netbird account (or use a setup key for Android)
3. In ATAK → TAK Server settings:
   - Address: Netbird IP of TAK Server (visible in Netbird dashboard → Peers)
   - Port: `8443`
   - SSL: enabled

---

## Notes

- Netbird peer-to-peer tunnels: After signalling, direct WireGuard tunnels are established
  between peers (no traffic through the management server).
- Works over any data link: cellular, satellite, tactical radio data.
- Self-hosted management plane can run in a Docker container on a separate node.
- For air-gapped deployments, use Netbird with self-hosted management on a node that has
  reach to all peers (e.g., via satellite uplink).
