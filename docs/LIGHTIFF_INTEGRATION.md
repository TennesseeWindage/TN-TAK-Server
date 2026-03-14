# LightIFF Integration

## Overview

TN-TAK-Server is the **coalition and cross-unit relay** for the LightIFF protocol suite.
While the LightIFF beacon and ATAK plugin handle local IFF operations over optical (IR/laser)
and BLE links, TAK Server is required when:

- Multiple squads or units need to share IFF keys and friend lists
- ATAK clients are on separate networks (Wi-Fi, cellular, satellite)
- IFF hit events need to be logged or forwarded to command
- Mission configuration needs to be pushed to all ATAK clients simultaneously

---

## LightIFF System Architecture

```
       LightIFF Targeting Computer (RZ/V2H)
       ┌──────────────────────────────────────────┐
       │                                          │
       │  BLE GATT                                │
       │  (IFF decode)  ATAK Plugin              │
       │       ↓           ↓  CoT                │
       │  LightIFF Beacon   │                     │
       │  (optical IFF)     │                     │
       │                    │                     │
       │             TN-TAK-Server (Docker)        │
       │                    │                     │
       └────────────────────┼─────────────────────┘
                            │  TCP 8443 (TLS)
             ┌──────────────┼──────────────────────┐
             │              │                      │
      ATAK Phone      ATAK Tablet           ATAK Phone
      (Squad 1)       (Hub Operator)        (Squad 2)
```

---

## LightIFF CoT Message Types Relayed by TAK Server

All LightIFF CoT message types are relayed by TAK Server as standard CoT XML.
No server-side plugin is required — TAK Server is transport only.

| CoT Type | Purpose | Typical Flow |
|----------|---------|-------------|
| `a-f-G-E-W-IFF` | Friendly IFF position event | Targeting computer → TAK Server → all ATAK clients |
| `a-h-G-E-W-IFF` | Hostile-not-in-friend-list interrogated | Targeting computer → TAK Server → squad leader |
| `IFF-KEY` | Allied IFF key share | Hub operator → TAK Server → squad ATAK clients |
| `IFF-FRIEND` | Friend list update | Hub → TAK Server → all |
| `IFF-HIT` | IFF hit notification | Any client → TAK Server → all |
| `IFF-CFG` | Mission configuration push | Hub → TAK Server → targeting computers |

Full CoT schema: [LightIFF/docs/ATAK_IFF_PROTOCOL.md](https://github.com/TennesseeWindage/LightIFF/blob/main/docs/ATAK_IFF_PROTOCOL.md)

---

## Typical Topology

### Forward Operating Base (FOB)

```
Android Hotspot (192.168.43.0/24)
│
├─ RZ/V2H Targeting Computer
│    ├─ TN-TAK-Server :8443
│    └─ LightIFF AI pipeline (DRP-AI3)
│
├─ ATAK Android (Squad 1)   192.168.43.x
├─ ATAK Android (Squad 2)   192.168.43.x
└─ ATAK Tablet (HQ)         192.168.43.x
```

### Multi-Unit Coalition

```
Internet / Satellite
│
├─ TAK Server (RZ/V2H, Tailscale: 100.x.y.z)
│    ├─ Squad 1 ATAK (Tailscale: 100.a.b.c)
│    └─ Squad 2 ATAK (Tailscale: 100.d.e.f)
│
└─ TAK Server (HQ, Tailscale: 100.p.q.r)   [Optional federation]
```

### Comms-Denied / EMCOM

```
LoRa Meshtastic mesh (~5–15 km range)
│
├─ Meshtastic Node (Squad 1)  →  CoT via bridge
├─ Meshtastic Node (Squad 2)  →  CoT via bridge
└─ RZ/V2H (Meshtastic bridge + TN-TAK-Server)
     └─ LightIFF beacons via BLE (< 100 m optical IFF)
```

---

## Quick Start

### Step 1: Configure TAK Server

```bash
cd TN-TAK-Server
cp config/CoreConfig.xml.template config/CoreConfig.xml
# Edit network/TAK settings if needed
./scripts/setup.sh
```

### Step 2: Install LightIFF-ATAK-Plugin on Android Devices

See [LightIFF-ATAK-Plugin README](https://github.com/TennesseeWindage/LightIFF-ATAK-Plugin/blob/main/README.md).

### Step 3: Connect ATAK Clients to TAK Server

ATAK → TAK Server settings → add server at TAK host IP, port 8443.

### Step 4: Push IFF Mission Configuration

From the hub operator's ATAK → LightIFF plugin → Mission Config → push `IFF-CFG` CoT.

This distributes beacon configurations (Level 1 ID, AES key) to all ATAK clients, which
forward the config to their locally connected beacons via BLE.

### Step 5: Begin IFF Operations

LightIFF beacons receive interrogation, respond with encrypted optical signal.
ATAK plugin decodes, emits `a-f-G-E-W-IFF` CoT → TAK Server → all clients see IFF overlay.

---

## Protocol Version Compatibility

| TN-TAK-Server | LightIFF Protocol | ATAK Plugin |
|---------------|------------------|-------------|
| Any           | 0.1.x            | 1.0.x       |

TAK Server is CoT transport only — it does not parse LightIFF CoT content.
Plugin-to-plugin compatibility is governed by `protocol_version` in CoT `<lightiff>` detail.
See [LightIFF CHANGELOG](https://github.com/TennesseeWindage/LightIFF/blob/main/CHANGELOG.md).

---

## References

- LightIFF Protocol Specification: [github.com/TennesseeWindage/LightIFF](https://github.com/TennesseeWindage/LightIFF)
- LightIFF ATAK Plugin: [github.com/TennesseeWindage/LightIFF-ATAK-Plugin](https://github.com/TennesseeWindage/LightIFF-ATAK-Plugin)
- TAK Product Center: [github.com/TAK-Product-Center](https://github.com/TAK-Product-Center)
- TAK.gov: [tak.gov](https://tak.gov)
