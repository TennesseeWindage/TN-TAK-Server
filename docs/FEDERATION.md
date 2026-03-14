# TAK Server Federation Guide

## Overview

TAK Server federation allows multiple TAK Server instances to share Cursor-on-Target (CoT)
events — including LightIFF `IFF-KEY`, `IFF-FRIEND`, `IFF-HIT`, and position events —
across networks and organizational boundaries.

```
  Squad A (FOB)                    HQ / Command Post
  ┌──────────────────┐             ┌──────────────────────┐
  │ TN-TAK-Server A  │◄──────────►│  TN-TAK-Server HQ    │
  │ (RZ/V2H)         │  Federated │  (cloud / x86_64)    │
  │ Tailscale: A-IP  │ Federation │  Tailscale: HQ-IP    │
  └──────────────────┘            └──────────────────────┘
        ▲                                   ▲
        │ CoT                               │ CoT
  ┌─────┴──────┐                    ┌───────┴──────┐
  │ ATAK Squad │                    │ ATAK HQ staff│
  └────────────┘                    └──────────────┘
```

---

## TAK 5.5 Federation Architecture

### Federation Modes

| Mode | Package | Port | Use |
|------|---------|------|-----|
| Direct peer-to-peer (v1) | TAK Server only | 8446 | Simple, legacy |
| Federation Hub (v2) | **Separate** `fed-hub` package | 9000/9001 | Multi-server, broker-based |

**Important**: Federation Hub is NOT bundled with TAK Server 5.5.
Download `takserver-fed-hub_5.5-RELEASE58_all.deb` separately from [tak.gov](https://tak.gov).

Federation Hub web UI runs on port 9100 and provides visibility into connected federates.

---

## Federation Over VPN (Recommended)

Using Tailscale or Netbird for federation links is strongly recommended because:

- No public internet port exposure
- WireGuard encryption in addition to TAK's own TLS
- Works over cellular, satellite, CGNAT without STUN/TURN
- Federation peers identified by stable VPN IP

### With Tailscale

1. Both TAK Servers must be on the same Tailscale network (tailnet)
2. Add `tag:tak-server` to both hosts in Tailscale ACL
3. Set the federation peer address to the Tailscale IP (`100.x.y.z`)

```xml
<!-- config/CoreConfig.xml — federation section -->
<federation v1Enabled="false" v2Enabled="true" enableFederation="true">
  <federate address="100.x.y.z" port="9001" fallback="false"
            id="remote-tak-hq" name="HQ TAK Server" v1="false" v2="true"/>
</federation>
```

```bash
# Setup Tailscale first
./scripts/setup-tailscale.sh

# Then configure federation
./scripts/setup-federation.sh \
    --remote-host 100.x.y.z \
    --remote-ca /path/to/remote-ca.pem
```

### With Netbird

Same pattern — use Netbird peer IP as federation address.

```bash
./scripts/setup-netbird.sh
./scripts/setup-federation.sh --remote-host <netbird-peer-ip> --remote-ca remote-ca.pem
```

### Without VPN (Direct Internet)

If neither Tailscale nor Netbird is available:

1. Open port `9001` on both servers' firewalls
2. Use the public IP as the federation address
3. Consider deploying coturn for NAT traversal (see `docs/ICE_STUN_TURN.md`)

---

## Step-by-Step Setup

### Step 1: Install Federation Hub (if using v2)

Download `takserver-fed-hub_5.5-RELEASE58_all.deb` from [tak.gov](https://tak.gov) and
place it in the repo root. The setup script will integrate it:

```bash
# Run main setup first if not done
./scripts/setup.sh

# Then enable federation
./scripts/setup-federation.sh
```

Or start the Federation Hub sidecar manually:

```bash
docker compose -f docker-compose.yml -f docker-compose.federation.yml up -d tak-fed-hub
```

### Step 2: Exchange CA Certificates

Each server must trust the other's CA:

**On Server A** — export CA:

```bash
cat tak/certs/files/ca.pem
# Share this with Server B operator securely (not over untrusted email)
```

**On Server B** — import Server A's CA:

```bash
keytool -importcert \
    -file server-a-ca.pem \
    -keystore tak/certs/files/fed-truststore.jks \
    -alias "tak-server-a" \
    -storepass atakatak \
    -noprompt
docker compose restart tak-server
```

Repeat in reverse (Server A imports Server B's CA).

### Step 3: Enable Federation in CoreConfig.xml

Edit `config/CoreConfig.xml`:

```xml
<federation v1Enabled="false" v2Enabled="true" enableFederation="true">
  <federate address="<REMOTE-VPN-IP-or-PUBLIC-IP>"
            port="9001"
            fallback="false"
            id="remote-tak-server"
            name="Remote TAK Server"
            v1="false"
            v2="true"/>
</federation>
```

Or run:

```bash
./scripts/setup-federation.sh --remote-host <ip> --remote-ca remote-ca.pem
```

### Step 4: Configure Federation Policy

Edit `config/federation/federation-hub-policy.json` to control which groups
are shared with federated servers.

For LightIFF, share the `LIGHTIFF` group:

```json
"outgoingGroups": [
  { "name": "LIGHTIFF", "enabled": true }
],
"incomingGroups": [
  { "remoteGroup": "LIGHTIFF", "localGroup": "LIGHTIFF", "enabled": true }
]
```

### Step 5: Verify Federation

Check Federation Hub web UI: `https://<server-ip>:9100`

Or check logs:

```bash
docker compose logs -f tak-fed-hub
# Look for: "Federation connection established to remote-tak-server"
```

---

## Firewall Ports for Federation

| Port | Protocol | Purpose |
|------|----------|---------|
| 9000 | TCP | Federation Hub v1 broker |
| 9001 | TCP | Federation Hub v2 broker (preferred) |
| 9100 | HTTPS | Federation Hub web UI (admin only) |
| 8446 | HTTPS | Direct peer-to-peer federation (without Hub) |

When using Tailscale/Netbird, these ports only need to be open on the VPN interface,
not on the public interface.

---

## Topology Patterns

### Pattern 1: Squad ↔ HQ Federation (Tailscale)

```
Squad FOB (RZ/V2H)          HQ Server (cloud VM)
Tailscale: 100.10.0.1       Tailscale: 100.10.0.2
         └──────── fed v2 port 9001 ──────────┘
```

### Pattern 2: Multi-Squad via Central Federation Hub

```
                   HQ Federation Hub
                   Tailscale: 100.10.0.2
                   ┌────────────────────┐
                   │  tak-fed-hub :9001 │
                   └──┬────────┬────────┘
                      │        │
          Squad A (FOB)        Squad B (FOB)
          100.10.0.3            100.10.0.4
```

### Pattern 3: Coalition Federation (Netbird + TURN)

```
Unit A (Netbird: A-IP)  ←→  Coturn TURN  ←→  Allied Unit B (Netbird: B-IP)
         ↓                                              ↓
  TN-TAK-Server A                            Allied TAK Server B
  (LightIFF targeting computer)               (standard TAK)
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Certificate not trusted" on connection | Exchange CA certs (Step 2 above); restart both servers |
| Federation Hub not starting | Download `takserver-fed-hub_5.5-RELEASE58_all.deb` from tak.gov |
| No events flowing between servers | Verify group policy in `federation-hub-policy.json`; check both servers have `LIGHTIFF` group |
| Connection refused on port 9001 | Check firewall; verify federation Hub is running (`docker compose ps`) |
| CoT not appearing on remote ATAK | Verify group assignment in TAK User Management; federated clients must be in same group |

---

## References

- [TAK Product Center — Server](https://github.com/TAK-Product-Center/Server)
- [TAK Server 5.5 Setup Guide](https://github.com/engindearing-projects/ogTAK-Server-Setup-Guides)
- [docs/TAILSCALE.md](TAILSCALE.md)
- [docs/NETBIRD.md](NETBIRD.md)
- [docs/ICE_STUN_TURN.md](ICE_STUN_TURN.md)
