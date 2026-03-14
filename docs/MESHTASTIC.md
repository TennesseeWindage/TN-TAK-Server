# Meshtastic Integration

## Overview

[Meshtastic](https://meshtastic.org) is an open-source LoRa mesh networking platform.
When combined with TN-TAK-Server, it provides a long-range, low-bandwidth,
infrastructure-free communications layer for ATAK situational awareness in comms-denied
environments.

```
┌─────────────────────┐       LoRa RF (~3–15 km)       ┌────────────────────┐
│  Meshtastic Node    │◄────────────────────────────────│  Meshtastic Nodes  │
│  (USB/UART to RZ)   │                                 │  (squad members)   │
└──────────┬──────────┘                                 └────────────────────┘
           │ Serial / TCP API
┌──────────┴──────────┐
│  Meshtastic-TAK      │
│  Bridge (Docker)     │ ← translates Meshtastic → CoT
└──────────┬──────────┘
           │ CoT UDP :8087
┌──────────┴──────────┐
│  TN-TAK-Server       │ ← relays CoT to ATAK clients
│  (Docker)            │
└─────────────────────┘
```

---

## Limitations

Meshtastic LoRa is **low bandwidth** (~250 bps effective throughput in some configurations).
It is suitable for:

- Position updates (PLI) — every 30–60 seconds per node
- Short text messages
- LightIFF IFF hit alerts (small CoT payloads)

It is **not suitable** for:
- Video or high-frequency data
- LightIFF optical IFF decode data (handled by BLE → ATAK directly, not via Meshtastic)

---

## Hardware

| Component | Notes |
|-----------|-------|
| Meshtastic LoRa radio | LILYGO T-Beam, Heltec LoRa32, RAK WisBlock, etc. |
| USB/UART connection | LoRa radio connected to RZ board via USB |
| Meshtastic firmware | [meshtastic.org/docs/getting-started](https://meshtastic.org/docs/getting-started/) |

---

## Setup

### 1. Flash Meshtastic firmware

Follow [meshtastic.org](https://meshtastic.org) instructions for your LoRa radio.
Configure the radio (region, channel, PSK) using the Meshtastic mobile app or CLI.

### 2. Connect LoRa Radio to RZ Board

- USB serial: plug in LoRa radio; verify `/dev/ttyUSB0` exists
- TCP: configure Meshtastic wifi settings; note `<ip>:4403`

### 3. Configure Bridge

```bash
cp config/meshtastic/meshtastic.env.example config/meshtastic/meshtastic.env
# Edit: MESH_DEVICE, TAK_HOST, TAK_PORT
```

### 4. Run Setup Script

```bash
chmod +x scripts/setup-meshtastic.sh
./scripts/setup-meshtastic.sh
```

Or start manually:

```bash
docker compose \
    -f docker-compose.yml \
    -f config/meshtastic/docker-compose.meshtastic.yml \
    up -d meshtastic-bridge
```

### 5. TAK Server CoT UDP Input

Enable UDP CoT input in `config/CoreConfig.xml`:

```xml
<connector port="8087" tls="false" _name="udp_input"/>
```

---

## Alternative Bridges

If the bridge image in `docker-compose.meshtastic.yml` is not available, use one of:

- [alphafox02/meshtastic_to_tak](https://github.com/alphafox02/meshtastic_to_tak) — Python bridge
- Manual Python script using `meshtastic` library and `takprotopy` library

Manual example:

```python
import meshtastic
import socket, xml.etree.ElementTree as ET

iface = meshtastic.SerialInterface("/dev/ttyUSB0")

def on_receive(packet, interface):
    if packet.get('decoded', {}).get('portnum') == 'POSITION_APP':
        pos = packet['decoded']['position']
        # Build a minimal CoT XML
        cot = f'''<event version="2.0"
            uid="MESH-{packet['from']}"
            type="a-f-G-E-W" time="..." start="..." stale="..."
            how="m-g">
            <point lat="{pos['latitude']}" lon="{pos['longitude']}"
                   hae="{pos.get('altitude', 0)}" ce="50" le="50"/>
            <detail><contact callsign="MESH-{packet['from']}"/></detail>
        </event>'''
        # Send to TAK Server
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.sendto(cot.encode(), ('localhost', 8087))

iface.add_receive_handler(on_receive)
```

---

## Topology

For LightIFF field use:

- Each squad member carries a Meshtastic node on their kit
- The RZ/V2H targeting computer runs the Meshtastic bridge
- ATAK clients show Meshtastic node positions as map tracks (limited update rate)
- LightIFF IFF events come via BLE → ATAK plugin; Meshtastic provides backup PLI when BLE
  range is exceeded or ATAK mesh is not available
