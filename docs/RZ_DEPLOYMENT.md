# RZ/V2H and RZ/V2N TAK Server Deployment Guide

## Overview

This guide covers deploying TN-TAK-Server on Renesas **RZ/V2H** and **RZ/V2N** edge AI
processors as part of a LightIFF targeting computer system.

```
┌──────────────────────────────────────────────────────────────┐
│                   RZ/V2H Targeting Computer                   │
│                                                               │
│  ┌──────────────────┐   ┌────────────────────────────────┐   │
│  │  LightIFF AI     │   │     TN-TAK-Server (Docker)     │   │
│  │  Pipeline        │   │                                │   │
│  │  (DRP-AI3 TOPS)  │   │  tak-server  tak-db (Postgres) │   │
│  └──────────────────┘   └────────────────────────────────┘   │
│                                   │                           │
│                           eth0 / wlan0                        │
└───────────────────────────────────┼───────────────────────────┘
                                    │
          ┌─────────────────────────┼─────────────────┐
          │                         │                  │
     ATAK Phone              ATAK Tablet        ATAK Phone
     (squad member)          (hub operator)     (squad member)
```

---

## Hardware

| Board | SoC | ARM cores | RAM | AI | Use |
|-------|-----|-----------|-----|----|-----|
| Renesas RZ/V2H EVK | RZ/V2H | 4x Cortex-A55 @ 1.8 GHz | 4 GB | DRP-AI3 8 TOPS | Full targeting computer (IFF + STANAG 7188 AI) |
| Renesas RZ/V2N EVK | RZ/V2N | 2x Cortex-A55 | 2 GB | DRP-AI2 | TAK Server + basic IFF decode; no high-fps AI |
| Custom SoM (e.g., Grinn ReneSOM-V2H) | RZ/V2H | same | 2–4 GB | DRP-AI3 | Compact form factor for rifle mounting |

---

## Prerequisites

### 1. OS

Official Renesas BSP (Yocto) or compatible Debian/Ubuntu ARM64 image.

- Verify: `uname -m` returns `aarch64`
- Verify: `cat /etc/os-release` shows a Debian/Ubuntu base or Yocto

### 2. Docker

```bash
# Install Docker (Debian-based)
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=arm64 signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
                        docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Test
docker run --rm hello-world
```

### 3. Resources

| Resource | RZ/V2H minimum | RZ/V2N minimum |
|----------|----------------|----------------|
| Available RAM for TAK container | 2 GB | 1 GB |
| Storage for TAK + PostgreSQL | 8 GB | 4 GB |
| Network | Ethernet or WiFi with DHCP or static IP | same |

---

## Setup

```bash
# Clone TN-TAK-Server
git clone https://github.com/TennesseeWindage/TN-TAK-Server.git
cd TN-TAK-Server

# Download TAK Server release from https://tak.gov/products/tak-server
# (account required) and place in repo root:
#   takserver-docker-5.5-RELEASE-58.zip

# Run setup (auto-detects arm64, applies ARM64 compose overrides)
chmod +x scripts/setup.sh
./scripts/setup.sh
```

### RZ/V2N vs RZ/V2H JVM tuning

Edit `docker-compose.arm64.yml` to switch the Dockerfile target:

| Board | Dockerfile | JAVA_OPTS Xmx |
|-------|------------|---------------|
| RZ/V2H | `Dockerfile.rzv2h` | `-Xmx1536m` |
| RZ/V2N | `Dockerfile.rzv2n` | `-Xmx768m` |

---

## Starting and Stopping

```bash
# Start (ARM64)
docker compose -f docker-compose.yml -f docker-compose.arm64.yml up -d

# Stop
docker compose down

# Restart after reboot (auto-start is configured by restart: unless-stopped)
# Or manually:
docker compose -f docker-compose.yml -f docker-compose.arm64.yml up -d

# Logs
docker compose logs -f tak-server
```

---

## ATAK Client Connection

1. Copy client cert package from `tak/certs/files/<username>.zip` to the Android device.
2. In ATAK: **Import → Local SD → .zip** (or use `scripts/shareCerts.sh` on trusted network).
3. TAK Server address: `<RZ-board-IP>:8443` (TLS).

---

## Network Configuration

### Static IP (recommended for fixed installations)

Edit `/etc/network/interfaces` or use `nmcli`:

```bash
sudo nmcli connection modify eth0 \
    ipv4.method manual \
    ipv4.addresses 192.168.1.100/24 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns "8.8.8.8"
sudo nmcli connection up eth0
```

### Firewall

```bash
# Allow TAK Server ports
sudo ufw allow 8443/tcp comment "TAK Server TLS"
sudo ufw allow 8444/tcp comment "TAK cert enrollment"
sudo ufw allow 8089/tcp comment "TAK legacy CoT (disable if not needed)"
```

---

## Performance Notes

- **RZ/V2H**: TAK Server runs comfortably at 2 GB heap with 20–50 simultaneous ATAK clients.
- **RZ/V2N**: Limit to 10–15 clients; reduce PostgreSQL `max_connections` to 30.
- TAK Server and the LightIFF AI pipeline (DRP-AI3) are independent Docker containers; allocate CPU/RAM via `deploy.resources` in `docker-compose.arm64.yml`.
- Monitor thermal: RZ boards may throttle under sustained load. Ensure adequate cooling for outdoor/vehicle deployments.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `docker: no matching manifest for linux/arm64` | Pull from Docker Hub requires Docker Buildx; run `docker buildx build --platform linux/arm64` |
| TAK Server fails to start — Out of memory | Reduce `-Xmx` in `docker-compose.arm64.yml`; free RAM on host |
| PostgreSQL health check fails | Check `docker compose logs tak-db`; ensure 512 MB RAM available |
| ATAK client cannot connect | Verify RZ board IP; check `ufw status`; confirm cert package imported |
