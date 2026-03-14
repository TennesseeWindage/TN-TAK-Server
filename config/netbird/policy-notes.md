# Netbird Policy Example
# Configure via the Netbird management dashboard (Policies tab) or management API.
# This file documents the recommended policies for TN-TAK-Server.
#
# Policy: TAK clients can reach TAK Server on TAK ports only.
#
# Group assignments:
#   tak-servers  — RZ boards / hosts running TN-TAK-Server
#   tak-clients  — ATAK Android devices with LightIFF plugin
#   admins       — Operators with full access

# Policy 1: tak-clients → tak-servers, ports 8443 8444 8446
#
# In Netbird dashboard:
#   Source: Group "tak-clients"
#   Destination: Group "tak-servers"
#   Protocol: TCP
#   Ports: 8443, 8444, 8446
#   Bidirectional: No (clients initiate)

# Policy 2: admins → tak-servers, all ports (SSH, web UI)
#
#   Source: Group "admins"
#   Destination: Group "tak-servers"
#   Protocol: All
#   Bidirectional: Yes

# To export/import policies via API:
#   curl -H "Authorization: Token <PAT>" https://api.netbird.io/api/policies
