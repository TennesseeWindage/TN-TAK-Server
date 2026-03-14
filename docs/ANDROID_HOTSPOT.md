# Android Hotspot Networking

## Overview

Android's built-in Wi-Fi hotspot creates a local subnet (typically `192.168.43.0/24`)
that ATAK clients and the LightIFF plugin can use to connect to TN-TAK-Server running
on a nearby host (RZ board, laptop, vehicle computer) without cellular or infrastructure
Wi-Fi.

```
┌────────────────────────────────────────────────────┐
│         Android Phone / Tablet (Hub Operator)       │
│                                                     │
│   ATAK  +  LightIFF-ATAK-Plugin                     │
│                                                     │
│   Wi-Fi Hotspot: 192.168.43.1                       │
└────────────────────────────────────────────────────┘
          │ (Wi-Fi 2.4 / 5 GHz)
          │
  ┌───────┴────────┐           ┌──────────────────────┐
  │  RZ/V2H Board  │           │  Other ATAK Clients   │
  │  (or laptop)   │           │  (phones, tablets)    │
  │  192.168.43.x  │           │  192.168.43.x         │
  │                │           └──────────────────────┘
  │  TN-TAK-Server │
  │  :8443 (TLS)   │
  └────────────────┘
```

---

## Setup

### Step 1: Enable Android Hotspot

1. Android Settings → Network → Hotspot & tethering → Wi-Fi hotspot
2. Set SSID and password (note them for field use)
3. Hotspot subnet is normally `192.168.43.0/24`; the Android device is `192.168.43.1`

### Step 2: Connect the RZ Board (or TAK host) to the Hotspot

```bash
# On the RZ board / TAK host
nmcli dev wifi connect "<SSID>" password "<PASSWORD>"

# Verify IP assignment in 192.168.43.0/24
ip addr show wlan0
```

### Step 3: Bind TAK Server to the Correct Address

TAK Server by default binds to all interfaces (`0.0.0.0`), which is correct for hotspot use.
Confirm in `config/CoreConfig.xml` that connectors do NOT specify a specific `address=` attribute
unless you want to restrict to one interface.

If you need to restrict to the hotspot interface only, add `address="192.168.43.X"` to each
connector in `CoreConfig.xml`:

```xml
<connector port="8443" tls="true" address="192.168.43.X" _name="https_legacy_input"/>
```

### Step 4: Configure Firewall

```bash
# Allow TAK ports from hotspot subnet
sudo ufw allow from 192.168.43.0/24 to any port 8443 proto tcp
sudo ufw allow from 192.168.43.0/24 to any port 8444 proto tcp
```

### Step 5: Distribute Certificates to ATAK Clients

**Option A — USB cable**: Copy `tak/certs/files/<user>.zip` to phone via USB.

**Option B — HTTP share** (trusted network only):

```bash
./scripts/shareCerts.sh
# Clients browse to http://192.168.43.X:12345 and download their .zip
```

**Option C — QR code / Airdrop**: Not supported natively; use `shareCerts.sh`.

### Step 6: Connect ATAK Clients

1. On each Android device, connect to the hotspot SSID.
2. In ATAK: **Settings → TAK Server → Add Server**
   - Address: `192.168.43.X` (TAK host IP on hotspot subnet)
   - Port: `8443`
   - SSL: enabled
   - Import the `.p12` certificate when prompted

---

## DHCP and IP Stability

Android hotspot DHCP leases may change between reboots.

**Options for stable TAK Server IP**:

1. **Static IP on the RZ/TAK host**:
   ```bash
   sudo nmcli connection modify "Hotspot-SSID" \
       ipv4.method manual \
       ipv4.addresses 192.168.43.100/24 \
       ipv4.gateway 192.168.43.1
   ```

2. **Android DHCP reservation**: Not available on all phones; use Option 1.

---

## Bandwidth Notes

| Scenario | Bandwidth | Notes |
|----------|-----------|-------|
| Squad (5–10 ATAK clients) | < 1 Mbps | CoT + LightIFF IFF events; well within hotspot capacity |
| Platoon (20–40 clients) | 2–5 Mbps | May need dedicated hotspot device (not phone) |
| Video / SA data | 5–20 Mbps | Video sharing over LightIFF pipeline; test on target hardware |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| ATAK cannot connect to TAK Server | Verify RZ board has hotspot IP; check `ufw status` |
| IP address changes after reconnect | Set static IP on RZ board as above |
| Hotspot range insufficient | Use external Wi-Fi adapter on RZ board; or dedicated hotspot device |
| Cert import fails in ATAK | Ensure `.zip` format; default password is `atakatak` |
