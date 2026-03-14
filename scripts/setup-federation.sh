#!/usr/bin/env bash
# Setup TAK Server federation for TN-TAK-Server
#
# TAK 5.5 federation requires the separate Federation Hub package:
#   takserver-fed-hub_5.5-RELEASE58_all.deb  (download from tak.gov)
#
# This script:
#   1. Verifies Federation Hub package is present
#   2. Exchanges CA certificates with a remote TAK server
#   3. Configures federation-hub-policy.json
#   4. Starts the Federation Hub sidecar
#
# Usage:
#   ./scripts/setup-federation.sh [--remote-ca /path/to/remote-ca.pem] [--remote-host 100.x.y.z]
#
# Federation over VPN (recommended):
#   Run after setup-tailscale.sh or setup-netbird.sh.
#   Remote server's VPN IP is used as the federation host — no public ports needed.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[federation]${NC} $*"; }
warn()  { echo -e "${YELLOW}[federation]${NC} $*"; }
error() { echo -e "${RED}[federation]${NC} $*"; exit 1; }

REMOTE_CA=""
REMOTE_HOST=""
REMOTE_PORT="9001"

# ── Parse args ────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote-ca)    REMOTE_CA="$2";   shift 2;;
    --remote-host)  REMOTE_HOST="$2"; shift 2;;
    --remote-port)  REMOTE_PORT="$2"; shift 2;;
    *) error "Unknown option: $1";;
  esac
done

# ── Verify TAK is set up ──────────────────────────────────────────────────
TAK_DIR="${REPO_DIR}/tak"
if [[ ! -d "${TAK_DIR}" ]]; then
  error "tak/ directory not found. Run scripts/setup.sh first."
fi

CERT_DIR="${TAK_DIR}/certs/files"
FED_TRUSTSTORE="${CERT_DIR}/fed-truststore.jks"
TRUSTSTORE_PASS="atakatak"

# ── Verify Federation Hub ─────────────────────────────────────────────────
FED_HUB_SCRIPT="${TAK_DIR}/federation-hub/scripts/federation-hub.sh"
if [[ ! -f "${FED_HUB_SCRIPT}" ]]; then
  warn "Federation Hub script not found at ${FED_HUB_SCRIPT}"
  warn ""
  warn "TAK Federation Hub is a SEPARATE package from TAK Server 5.5."
  warn "Download takserver-fed-hub_5.5-RELEASE58_all.deb from https://tak.gov"
  warn "Install it into the same tak/ directory before proceeding."
  warn ""
  warn "For direct peer-to-peer federation (without Federation Hub),"
  warn "set enableFederation=true in config/CoreConfig.xml and exchange CA certs below."
fi

# ── Export this server's CA certificate ──────────────────────────────────
LOCAL_CA_PEM="${CERT_DIR}/ca.pem"
if [[ -f "${LOCAL_CA_PEM}" ]]; then
  info "Local CA certificate: ${LOCAL_CA_PEM}"
  info "Share this with the remote TAK server operator for mutual trust."
  info ""
  info "Remote operator should run:"
  info "  keytool -importcert -file ca.pem -keystore fed-truststore.jks \\"
  info "          -alias '<this-server-name>' -storepass atakatak"
  info ""
else
  warn "Local CA not found at ${LOCAL_CA_PEM}. Run setup.sh to generate certificates first."
fi

# ── Import remote CA certificate ──────────────────────────────────────────
if [[ -n "${REMOTE_CA}" ]]; then
  if [[ ! -f "${REMOTE_CA}" ]]; then
    error "Remote CA file not found: ${REMOTE_CA}"
  fi
  REMOTE_ALIAS="$(basename "${REMOTE_CA}" .pem)"
  info "Importing remote CA: ${REMOTE_CA} → alias '${REMOTE_ALIAS}'"
  keytool -importcert \
      -file "${REMOTE_CA}" \
      -keystore "${FED_TRUSTSTORE}" \
      -alias "${REMOTE_ALIAS}" \
      -storepass "${TRUSTSTORE_PASS}" \
      -noprompt
  info "Remote CA imported into ${FED_TRUSTSTORE}"
fi

# ── Add remote server to federation-hub-policy.json ──────────────────────
POLICY_FILE="${REPO_DIR}/config/federation/federation-hub-policy.json"
if [[ -n "${REMOTE_HOST}" ]]; then
  info "Remote federation host: ${REMOTE_HOST}:${REMOTE_PORT}"
  info ""
  info "Add the following to ${POLICY_FILE} under federationOutgoing:"
  echo ""
  cat <<EOF
  {
    "name": "remote-tak-$(echo "${REMOTE_HOST}" | tr '.' '-')",
    "host": "${REMOTE_HOST}",
    "port": ${REMOTE_PORT},
    "enabled": true,
    "tlsVersion": "TLSv1.3"
  }
EOF
  echo ""
  info "Also enable federation in config/CoreConfig.xml:"
  info "  Change: enableFederation=\"false\""
  info "  To:     enableFederation=\"true\""
fi

# ── Enable federation in CoreConfig.xml ───────────────────────────────────
CONFIG="${REPO_DIR}/config/CoreConfig.xml"
if [[ -f "${CONFIG}" ]]; then
  if grep -q 'enableFederation="false"' "${CONFIG}"; then
    read -rp "Enable federation in CoreConfig.xml now? [y/N]: " ENABLE_FED
    if [[ "${ENABLE_FED}" =~ ^[Yy]$ ]]; then
      sed -i 's/enableFederation="false"/enableFederation="true"/' "${CONFIG}"
      info "Federation enabled in CoreConfig.xml"
      info "Restart TAK Server: docker compose restart tak-server"
    fi
  else
    info "Federation already enabled (or not found) in CoreConfig.xml"
  fi
fi

# ── Start Federation Hub ──────────────────────────────────────────────────
info ""
info "To start Federation Hub sidecar:"
info "  docker compose -f docker-compose.yml -f docker-compose.federation.yml up -d"
info ""
info "Federation Hub web UI: https://<server-ip>:9100"
info ""
info "See docs/FEDERATION.md for full setup guide."
