# ICE / STUN / TURN for TN-TAK-Server

## Overview

TAK Server federation peers need network connectivity to exchange CoT.
When peers are on the same LAN or VPN (Tailscale/Netbird), direct TCP connections work.
When peers are on different networks with NAT, ICE/STUN/TURN provides NAT traversal.

| Protocol | Role | Required? |
|----------|------|-----------|
| **STUN** | Discovers public IP/port of each peer | Yes for NAT traversal |
| **TURN** | Relay server when direct path fails | Only under symmetric NAT |
| **ICE** | Framework that uses STUN/TURN automatically | Used by Netbird and WebRTC-based tools |

---

## When Do You Need STUN/TURN?

| Network topology | Recommendation |
|-----------------|----------------|
| Both servers on same LAN / hotspot | No STUN/TURN needed |
| Both servers on Tailscale (same tailnet) | No STUN/TURN — WireGuard handles NAT |
| Both servers on Netbird | No STUN/TURN — Netbird's ICE handles NAT |
| One server behind carrier NAT (CGNAT) | STUN needed; TURN may be needed |
| Satellite uplink (VSAT) with symmetric NAT | TURN relay required |
| Air-gapped with no internet | Self-hosted STUN/TURN on local LAN |

**Recommendation**: Use Tailscale or Netbird for all federation links when possible.
STUN/TURN is a fallback for clients that cannot run Tailscale/Netbird.

---

## Deployment Options

### Option A — Self-Hosted coturn

Run [coturn](https://github.com/coturn/coturn) as a Docker sidecar on this server
or a separate host with a public IP.

```bash
cp config/coturn/coturn.env.example config/coturn/coturn.env
# Edit COTURN_PUBLIC_IP, COTURN_REALM
./scripts/setup-coturn.sh --mode self
```

Start:

```bash
docker compose -f docker-compose.yml -f docker-compose.coturn.yml up -d coturn
```

**Firewall** (self-hosted):

```bash
sudo ufw allow 3478/udp comment "STUN/TURN"
sudo ufw allow 3478/tcp comment "STUN/TURN TCP"
sudo ufw allow 5349/udp comment "TURN TLS"
sudo ufw allow 5349/tcp comment "TURN TLS"
sudo ufw allow 49152:65535/udp comment "TURN relay ports"
```

---

### Option B — Google STUN (Free, No Relay)

Use Google's public STUN servers for peer discovery only.
No TURN relay — will not work under symmetric NAT.

```
stun:stun.l.google.com:19302
stun:stun1.l.google.com:19302
```

Run:

```bash
./scripts/setup-coturn.sh --mode google
```

Configure TAK federation peer hosts to use this STUN address in their network settings.

**Limitations**:
- STUN only; no relay
- Requires outbound internet access
- Will fail under carrier-grade NAT (CGNAT) without TURN

---

### Option C — Tennessee Windage Hosted TURN

Tennessee Windage provides a hosted coturn server for LightIFF deployments.

**Contact**: support@tennesseewindage.com to request TURN credentials.

```bash
cp config/coturn/coturn.env.example config/coturn/coturn.env
# Set TN_TURN_USER and TN_TURN_PASS from credentials provided
./scripts/setup-coturn.sh --mode tn-hosted
```

Server details:

| Setting | Value |
|---------|-------|
| STUN/TURN host | `turn.tennesseewindage.com` |
| STUN port | `3478` |
| TURN TLS port | `5349` |
| Realm | `tak.tennesseewindage.com` |

---

## Integration with Tailscale / Netbird

When using Tailscale or Netbird for VPN, coturn is optional. However:

- **Internal TURN** (Tailscale-only): Deploy coturn and bind `external-ip` to the Tailscale
  IP (`100.x.y.z`) so only tailnet peers can use it. This provides relay for clients that
  can't establish direct Tailscale peer-to-peer connections (e.g., double-NAT cellular).

- **Netbird + coturn**: Netbird uses ICE internally, but a coturn TURN server can be
  configured as Netbird's TURN relay by setting `--turn-address` in Netbird management config.

### Example: coturn on Tailscale (VPN-internal TURN)

```
config/coturn/turnserver.conf:
  external-ip=100.x.y.z       (Tailscale IP of coturn host)
  realm=tak-internal
  listening-ip=0.0.0.0
  # Only VPN clients can reach this; no internet exposure needed
```

---

## Federation STUN/TURN Usage

TAK Server itself uses TCP for federation (port 9000/9001 via Federation Hub).
STUN/TURN is relevant for:

1. **ATAK client connectivity**: When ATAK clients use TAK Server over cellular with CGNAT.
2. **Netbird ICE**: Netbird uses ICE to establish WireGuard tunnels; a local TURN relay
   improves reliability in high-loss or symmetric NAT environments.
3. **Future WebRTC-based TAK extensions**: Video/audio streams within ATAK ecosystem.

---

## Verifying coturn

```bash
# Test STUN (requires turnutils_stunclient from coturn package)
turnutils_stunclient -p 3478 <server-ip>

# Test TURN allocation
turnutils_uclient -T -p 3478 \
    -u <turn-user> -w <turn-pass> \
    <server-ip>

# From outside: check ports open
nmap -sU -p 3478 <server-ip>
```
