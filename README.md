# TN-TAK-Server

**TAK Server 5.5 Docker deployment for LightIFF targeting computer systems.**

Optimized for Renesas **RZ/V2H** and **RZ/V2N** edge AI processors (ARM64 Cortex-A55) and
standard x86_64 Linux. Provides a turnkey TAK Server with SSL, PostgreSQL 15, federation,
and optional overlay networks for disconnected and semi-connected operations.

> **TAK Server 5.5** — latest supported release.
> Download `takserver-docker-5.5-RELEASE-58.zip` from [tak.gov](https://tak.gov/products/tak-server).

## Quick Start

```bash
# 1. Download TAK Server 5.5 from https://tak.gov/products/tak-server
#    (free registration required)
#    Place the ZIP in the repo root:
#      takserver-docker-5.5-RELEASE-58.zip

# 2. Run setup (auto-detects arch; applies ARM64 overrides on RZ boards)
chmod +x scripts/setup.sh
./scripts/setup.sh

# 3. Web UI (after setup): https://<server-ip>:8443
#    Import tak/certs/files/admin.p12 (password: atakatak)
```

## Platform Support

| Platform | Architecture | Notes |
|----------|-------------|-------|
| Renesas RZ/V2H | linux/arm64 | 4x Cortex-A55, DRP-AI3 8 TOPS; LightIFF targeting computer |
| Renesas RZ/V2N | linux/arm64 | Lower-spec; TAK Server only, no AI inference on-board |
| x86_64 Linux | linux/amd64 | Development, HQ server, cloud VM |

ARM64 deployments: `docker compose -f docker-compose.yml -f docker-compose.arm64.yml up -d`

See [docs/RZ_DEPLOYMENT.md](docs/RZ_DEPLOYMENT.md) for RZ board setup.

---

## TAK Server 5.5 Requirements

| Requirement | Version | Notes |
|-------------|---------|-------|
| Java | 17 (Temurin/OpenJDK) | Bundled in Docker image |
| PostgreSQL | **15 only** | 16 will fail; `postgres:15-alpine` pinned in compose |
| TAK Server | 5.5-RELEASE-58 | Download from [tak.gov](https://tak.gov) |
| Federation Hub | 5.5-RELEASE-58 | **Separate package** — `takserver-fed-hub_5.5-RELEASE58_all.deb` |

> **Critical gotcha**: Ubuntu 24.04 defaults to PostgreSQL 16. The Docker compose file
> explicitly pins `postgres:15-alpine`. Do not override this.

---

## Networking Options

| Option | Use case | Setup |
|--------|----------|-------|
| Local LAN | Squad/platoon on shared network | (default) |
| Android hotspot | Forward operating base, no infrastructure | [docs/ANDROID_HOTSPOT.md](docs/ANDROID_HOTSPOT.md) |
| Tailscale | Remote/coalition, WireGuard mesh VPN | [scripts/setup-tailscale.sh](scripts/setup-tailscale.sh) |
| Netbird | Zero-trust mesh VPN, self-hostable | [scripts/setup-netbird.sh](scripts/setup-netbird.sh) |
| Meshtastic (LoRa) | Comms-denied, EMCOM; TAK over LoRa | [scripts/setup-meshtastic.sh](scripts/setup-meshtastic.sh) |

---

## Federation

TAK Server federation enables CoT sharing (IFF-KEY, IFF-FRIEND, IFF-HIT) across
squad, platoon, and coalition networks.

| Feature | Compose file | Script |
|---------|-------------|--------|
| Federation Hub sidecar | `docker-compose.federation.yml` | `scripts/setup-federation.sh` |
| CA certificate exchange | — | `scripts/setup-federation.sh --remote-ca` |
| Federation over Tailscale | Tailscale + federation | Both setup scripts |
| Federation over Netbird | Netbird + federation | Both setup scripts |

```bash
# Start with Federation Hub
docker compose -f docker-compose.yml -f docker-compose.federation.yml up -d

# Configure remote server
./scripts/setup-federation.sh \
    --remote-host 100.x.y.z \
    --remote-ca /path/to/remote-ca.pem
```

Federation Hub web UI: `https://<server-ip>:9100`

See [docs/FEDERATION.md](docs/FEDERATION.md) for the full guide.

---

## ICE / STUN / TURN

For federation across NAT or CGNAT (cellular/satellite), coturn provides NAT traversal.

| Option | Command | Notes |
|--------|---------|-------|
| Self-hosted coturn | `./scripts/setup-coturn.sh --mode self` | Full control; runs on RZ board or VM |
| Google STUN (free) | `./scripts/setup-coturn.sh --mode google` | STUN only; no relay; no CGNAT support |
| Tennessee Windage hosted TURN | `./scripts/setup-coturn.sh --mode tn-hosted` | Credentials on request |

**Recommendation**: Use Tailscale or Netbird instead of STUN/TURN when possible.
STUN/TURN is a fallback for satellite and CGNAT scenarios.

See [docs/ICE_STUN_TURN.md](docs/ICE_STUN_TURN.md).

---

## LightIFF Integration

This TAK Server is the **coalition and cross-unit relay** for the LightIFF protocol suite.

- Relays `IFF-KEY`, `IFF-FRIEND`, `IFF-HIT`, `IFF-CFG` CoT between ATAK clients
- No server-side plugin required — TAK Server is CoT transport only
- See [docs/LIGHTIFF_INTEGRATION.md](docs/LIGHTIFF_INTEGRATION.md)
- LightIFF protocol spec: [https://repos.fyberlabs.com/tennessee-windage?LightIFF](https://repos.fyberlabs.com/tennessee-windage?LightIFF)
- ATAK plugin: [https://repos.fyberlabs.com/tennessee-windage?LightIFF-ATAK-Plugin](https://repos.fyberlabs.com/tennessee-windage?LightIFF-ATAK-Plugin)

---

## Repository Structure

```
TN-TAK-Server/
├── docker/
│   ├── Dockerfile              # Multi-arch: amd64, arm64
│   ├── Dockerfile.rzv2h        # RZ/V2H JVM tuning
│   └── Dockerfile.rzv2n        # RZ/V2N JVM tuning
├── docker-compose.yml          # Base: tak-server + tak-db (PostgreSQL 15)
├── docker-compose.arm64.yml    # ARM64 overrides (RZ boards)
├── docker-compose.federation.yml  # Federation Hub sidecar
├── docker-compose.coturn.yml   # coturn ICE/STUN/TURN sidecar
├── scripts/
│   ├── setup.sh                # Main setup
│   ├── setup-federation.sh     # Federation: CA exchange, CoreConfig, Fed Hub
│   ├── setup-coturn.sh         # ICE/STUN/TURN: self-hosted / Google / TN-hosted
│   ├── setup-tailscale.sh      # Tailscale VPN
│   ├── setup-netbird.sh        # Netbird VPN
│   ├── setup-meshtastic.sh     # Meshtastic LoRa bridge
│   └── shareCerts.sh           # HTTP cert sharing (trusted network only)
├── config/
│   ├── CoreConfig.xml.template # TAK Server config (TLS, PG, federation)
│   ├── federation/             # Federation Hub policy, cert notes
│   ├── coturn/                 # coturn config, certs, env
│   ├── tailscale/              # Tailscale ACL
│   ├── netbird/                # Netbird policy
│   └── meshtastic/             # Meshtastic bridge config
├── docs/
│   ├── RZ_DEPLOYMENT.md
│   ├── FEDERATION.md
│   ├── ICE_STUN_TURN.md
│   ├── ANDROID_HOTSPOT.md
│   ├── TAILSCALE.md
│   ├── NETBIRD.md
│   ├── MESHTASTIC.md
│   └── LIGHTIFF_INTEGRATION.md
├── tak-md5checksum.txt         # Checksums for supported TAK releases
└── tak-sha1checksum.txt
```

---

## References

- [TAK Product Center](https://github.com/TAK-Product-Center)
- [Cloud-RF/tak-server](https://github.com/Cloud-RF/tak-server) — Docker wrapper reference
- [TAK Server 5.5 Setup Guides](https://github.com/engindearing-projects/ogTAK-Server-Setup-Guides)
- [TAK.gov](https://tak.gov)
- [coturn](https://github.com/coturn/coturn) — STUN/TURN server
