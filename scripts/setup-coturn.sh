#!/usr/bin/env bash
# Setup coturn ICE/STUN/TURN server for TN-TAK-Server federation
#
# Provides STUN (NAT traversal discovery) and TURN (relay) services for:
#   - TAK federation peer connectivity across NAT
#   - ATAK client connectivity over cellular/satellite when direct path unavailable
#
# Deployment options (configured in config/coturn/coturn.env):
#   A) Self-hosted (this script) — full control, runs on RZ board or cloud VM
#   B) Google STUN (free, STUN only) — stun:stun.l.google.com:19302
#   C) Tennessee Windage hosted TURN — credentials provisioned on request
#
# Usage: ./scripts/setup-coturn.sh [--mode self|google|tn-hosted]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_DIR}/config/coturn/coturn.env"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[coturn]${NC} $*"; }
warn()  { echo -e "${YELLOW}[coturn]${NC} $*"; }
error() { echo -e "${RED}[coturn]${NC} $*"; exit 1; }

MODE="${1:-}"
# ── Mode selection ────────────────────────────────────────────────────────
if [[ -z "${MODE}" ]]; then
  echo ""
  echo "  STUN/TURN deployment mode:"
  echo "  1) self      — Self-hosted coturn (this machine)"
  echo "  2) google    — Google STUN only (free; no TURN relay)"
  echo "  3) tn-hosted — Tennessee Windage hosted TURN (credentials required)"
  echo ""
  read -rp "Select mode [1/2/3]: " MODE_NUM
  case "${MODE_NUM}" in
    1) MODE="self";;
    2) MODE="google";;
    3) MODE="tn-hosted";;
    *) error "Invalid selection";;
  esac
fi

# ── Load env file ─────────────────────────────────────────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
  cp "${REPO_DIR}/config/coturn/coturn.env.example" "${ENV_FILE}"
fi
# shellcheck disable=SC1090
source "${ENV_FILE}"

case "${MODE}" in

  # ── Self-hosted coturn ────────────────────────────────────────────────
  self)
    info "Setting up self-hosted coturn..."

    # Determine public IP
    if [[ -z "${COTURN_PUBLIC_IP:-}" ]]; then
      DETECTED_IP="$(curl -fsSL https://api.ipify.org 2>/dev/null || \
                     ip -4 route get 1.1.1.1 | awk '{print $7}' | head -1)"
      read -rp "  Public IP [${DETECTED_IP}]: " COTURN_PUBLIC_IP
      COTURN_PUBLIC_IP="${COTURN_PUBLIC_IP:-${DETECTED_IP}}"
      sed -i "s/^COTURN_PUBLIC_IP=.*/COTURN_PUBLIC_IP=${COTURN_PUBLIC_IP}/" "${ENV_FILE}"
    fi

    # TURN user password
    if [[ -z "${COTURN_TURN_PASS:-}" ]]; then
      COTURN_TURN_PASS="$(openssl rand -hex 16)"
      sed -i "s/^COTURN_TURN_PASS=.*/COTURN_TURN_PASS=${COTURN_TURN_PASS}/" "${ENV_FILE}"
      info ""
      info "  TURN credentials: ${COTURN_TURN_USER}:${COTURN_TURN_PASS}"
      info "  SAVE THESE — they will not be shown again."
      info ""
    fi

    # Write turnserver.conf from template
    CONF_DEST="${REPO_DIR}/config/coturn/turnserver.conf"
    if [[ ! -f "${CONF_DEST}" ]]; then
      cp "${REPO_DIR}/config/coturn/turnserver.conf.template" "${CONF_DEST}"
      sed -i "s/{{PUBLIC_IP}}/${COTURN_PUBLIC_IP}/g" "${CONF_DEST}"
      sed -i "s/{{REALM}}/${COTURN_REALM:-tak.tennesseewindage.com}/g" "${CONF_DEST}"
      info "turnserver.conf written."
    fi

    # TLS certificates — reuse TAK certs or generate self-signed
    CERT_DIR="${REPO_DIR}/config/coturn/certs"
    mkdir -p "${CERT_DIR}"
    if [[ ! -f "${CERT_DIR}/turn_server_cert.pem" ]]; then
      info "Generating self-signed TLS cert for coturn (valid 10 years)..."
      openssl req -newkey rsa:2048 -nodes -x509 -days 3650 \
          -subj "/CN=${COTURN_PUBLIC_IP}" \
          -keyout "${CERT_DIR}/turn_server_pkey.pem" \
          -out "${CERT_DIR}/turn_server_cert.pem"
      chmod 600 "${CERT_DIR}/turn_server_pkey.pem"
      info "Self-signed cert written to ${CERT_DIR}/"
    fi

    # Start coturn
    info "Starting coturn container..."
    cd "${REPO_DIR}"
    docker compose -f docker-compose.yml -f docker-compose.coturn.yml up -d coturn

    info ""
    info "STUN: stun:${COTURN_PUBLIC_IP}:3478"
    info "TURN: turn:${COTURN_PUBLIC_IP}:3478  user=${COTURN_TURN_USER}  pass=${COTURN_TURN_PASS}"
    info "TURN TLS: turns:${COTURN_PUBLIC_IP}:5349"
    ;;

  # ── Google STUN (no relay) ───────────────────────────────────────────
  google)
    info "Using Google STUN (free, STUN only — no TURN relay)."
    info ""
    info "STUN server: stun:stun.l.google.com:19302"
    info "            stun:stun1.l.google.com:19302"
    info ""
    info "Configure TAK federation peers to use Google STUN in their ATAK settings."
    info "Note: STUN alone will not work behind symmetric NAT."
    info "      Use Tailscale, Netbird, or a TURN relay for full NAT traversal."
    info ""
    warn "No coturn container will be started in Google STUN mode."
    ;;

  # ── Tennessee Windage hosted TURN ────────────────────────────────────
  tn-hosted)
    info "Configuring Tennessee Windage hosted TURN server."
    info ""
    if [[ -z "${TN_TURN_USER:-}" ]] || [[ -z "${TN_TURN_PASS:-}" ]]; then
      warn "TN_TURN_USER / TN_TURN_PASS not set in ${ENV_FILE}"
      warn "Contact Tennessee Windage to provision TURN credentials."
      warn "Email: support@tennesseewindage.com"
    else
      info "TURN: turn:${TN_TURN_HOST:-turn.tennesseewindage.com}:${TN_TURN_PORT:-3478}"
      info "TURN TLS: turns:${TN_TURN_HOST:-turn.tennesseewindage.com}:${TN_TURN_TLS_PORT:-5349}"
      info "User: ${TN_TURN_USER}"
    fi
    info ""
    info "Configure TAK federation peers with these credentials."
    info "No local coturn container needed."
    ;;

  *)
    error "Unknown mode: ${MODE}. Use: self | google | tn-hosted"
    ;;
esac
