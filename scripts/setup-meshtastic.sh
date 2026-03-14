#!/usr/bin/env bash
# Setup Meshtastic-to-TAK bridge for TN-TAK-Server
#
# Meshtastic provides long-range LoRa mesh networking. This script sets up the
# meshtastic-python gateway or the meshtastic-tak bridge (if available) as a
# Docker sidecar that translates Meshtastic position and text messages to
# TAK CoT and forwards them to the local TAK Server.
#
# Usage: ./scripts/setup-meshtastic.sh
# Requires: config/meshtastic/meshtastic.env (copy from meshtastic.env.example)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_DIR}/config/meshtastic/meshtastic.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[meshtastic]${NC} $*"; }
warn()  { echo -e "${YELLOW}[meshtastic]${NC} $*"; }
error() { echo -e "${RED}[meshtastic]${NC} $*"; exit 1; }

# ── Configuration ─────────────────────────────────────────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
  warn "config/meshtastic/meshtastic.env not found; copying from example"
  cp "${REPO_DIR}/config/meshtastic/meshtastic.env.example" "${ENV_FILE}"
  error "Edit ${ENV_FILE} with your Meshtastic device connection settings, then re-run."
fi
# shellcheck disable=SC1090
source "${ENV_FILE}"

MESH_DEVICE="${MESH_DEVICE:-/dev/ttyUSB0}"  # Serial port or TCP host:port
TAK_HOST="${TAK_HOST:-localhost}"
TAK_PORT="${TAK_PORT:-8087}"                # TAK Server CoT UDP port

# ── Check for Meshtastic device ───────────────────────────────────────────
if [[ "${MESH_DEVICE}" == /dev/* ]]; then
  if [[ ! -e "${MESH_DEVICE}" ]]; then
    error "Meshtastic device ${MESH_DEVICE} not found.\nConnect the LoRa radio and verify with: ls /dev/ttyUSB*"
  fi
  info "Meshtastic device: ${MESH_DEVICE}"
else
  info "Meshtastic TCP connection: ${MESH_DEVICE}"
fi

# ── Install meshtastic Python package ────────────────────────────────────
if ! python3 -c "import meshtastic" 2>/dev/null; then
  info "Installing meshtastic Python library..."
  pip3 install --user meshtastic
fi

# ── Launch bridge as Docker sidecar ──────────────────────────────────────
info "Starting Meshtastic-TAK bridge container..."

# The bridge image translates Meshtastic position and nodeinfo to CoT
# and forwards to TAK Server UDP port 8087 (CoT direct XML, no TLS).
#
# If a dedicated meshtastic-tak Docker image is available, use it:
#   docker run --rm -d --device ${MESH_DEVICE} \
#       -e TAK_HOST=${TAK_HOST} -e TAK_PORT=${TAK_PORT} \
#       meshtastic/tak-bridge:latest
#
# Otherwise, use the meshtastic-python gateway script in config/meshtastic/:
cd "${REPO_DIR}"
docker compose -f docker-compose.yml -f config/meshtastic/docker-compose.meshtastic.yml up -d meshtastic-bridge

info ""
info "Meshtastic bridge started."
info "CoT from LoRa mesh will be forwarded to TAK Server at ${TAK_HOST}:${TAK_PORT}"
info ""
warn "Note: The Meshtastic-TAK bridge is an optional, community-supported component."
warn "For manual setup or alternative bridges, see docs/MESHTASTIC.md"
