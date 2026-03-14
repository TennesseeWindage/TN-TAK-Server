#!/usr/bin/env bash
# Setup Tailscale sidecar for TN-TAK-Server
#
# Tailscale provides a WireGuard-based mesh VPN so ATAK clients on remote networks
# (coalition, command post, HQ) can reach this TAK Server securely.
#
# Usage: ./scripts/setup-tailscale.sh
# Requires: Tailscale auth key in config/tailscale/authkey
#           (generate at https://login.tailscale.com/admin/settings/keys)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTHKEY_FILE="${REPO_DIR}/config/tailscale/authkey"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[tailscale]${NC} $*"; }
warn()  { echo -e "${YELLOW}[tailscale]${NC} $*"; }
error() { echo -e "${RED}[tailscale]${NC} $*"; exit 1; }

# ── Auth key ──────────────────────────────────────────────────────────────
if [[ ! -f "${AUTHKEY_FILE}" ]]; then
  error "Tailscale auth key not found at ${AUTHKEY_FILE}.\nGenerate one at https://login.tailscale.com/admin/settings/keys\nand write it to ${AUTHKEY_FILE} (chmod 600)"
fi
TS_AUTHKEY="$(cat "${AUTHKEY_FILE}")"

# ── Install Tailscale on host (if not present) ────────────────────────────
if ! command -v tailscale &>/dev/null; then
  info "Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
else
  info "Tailscale already installed: $(tailscale --version | head -1)"
fi

# ── Start tailscaled ──────────────────────────────────────────────────────
if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
  info "Starting tailscaled..."
  sudo systemctl enable --now tailscaled
fi

# ── Authenticate ──────────────────────────────────────────────────────────
TS_FLAGS="--accept-routes --advertise-tags=tag:tak-server"
info "Authenticating with Tailscale..."
sudo tailscale up --authkey="${TS_AUTHKEY}" ${TS_FLAGS}

TS_IP="$(tailscale ip -4 2>/dev/null || echo 'pending')"
info "Tailscale IP: ${TS_IP}"
info ""
info "ATAK clients should connect to: ${TS_IP}:8443"
info ""
info "Ensure TAK Server clients have:"
info "  1. Tailscale installed on their device"
info "  2. Joined the same Tailscale network (tailnet)"
info "  3. TAK Server address set to ${TS_IP}:8443 in ATAK"
