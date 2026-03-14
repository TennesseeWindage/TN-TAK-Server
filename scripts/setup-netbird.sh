#!/usr/bin/env bash
# Setup Netbird for TN-TAK-Server
#
# Netbird is a zero-trust mesh VPN (WireGuard-based) with a self-hostable
# management plane (alternative to Tailscale for air-gapped deployments).
#
# Usage: ./scripts/setup-netbird.sh
# Requires: config/netbird/setup-key (generate at your Netbird management URL)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_KEY_FILE="${REPO_DIR}/config/netbird/setup-key"
NB_CONFIG="${REPO_DIR}/config/netbird/netbird.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[netbird]${NC} $*"; }
warn()  { echo -e "${YELLOW}[netbird]${NC} $*"; }
error() { echo -e "${RED}[netbird]${NC} $*"; exit 1; }

# ── Setup key ─────────────────────────────────────────────────────────────
if [[ ! -f "${SETUP_KEY_FILE}" ]]; then
  error "Netbird setup key not found at ${SETUP_KEY_FILE}.\nGenerate one in the Netbird management dashboard.\nWrite it to ${SETUP_KEY_FILE} (chmod 600)."
fi
NB_SETUP_KEY="$(cat "${SETUP_KEY_FILE}")"

# ── Management URL ────────────────────────────────────────────────────────
if [[ -f "${NB_CONFIG}" ]]; then
  # shellcheck disable=SC1090
  source "${NB_CONFIG}"
fi
NB_MANAGEMENT_URL="${NB_MANAGEMENT_URL:-https://api.netbird.io}"

# ── Install Netbird ───────────────────────────────────────────────────────
if ! command -v netbird &>/dev/null; then
  info "Installing Netbird..."
  curl -fsSL https://pkgs.netbird.io/install.sh | sh
else
  info "Netbird already installed: $(netbird version 2>/dev/null || echo unknown)"
fi

# ── Start and connect ─────────────────────────────────────────────────────
info "Starting Netbird service..."
sudo systemctl enable --now netbird

info "Connecting to ${NB_MANAGEMENT_URL}..."
sudo netbird up \
    --setup-key "${NB_SETUP_KEY}" \
    --management-url "${NB_MANAGEMENT_URL}"

NB_IP="$(netbird status 2>/dev/null | grep 'NetBird IP:' | awk '{print $NF}' || echo 'pending')"
info "Netbird IP: ${NB_IP}"
info ""
info "ATAK clients should connect to: ${NB_IP}:8443"
info "Ensure clients are connected to the same Netbird network."
