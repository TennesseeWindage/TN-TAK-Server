#!/usr/bin/env bash
# TN-TAK-Server setup script
#
# Usage: ./scripts/setup.sh
#
# 1. Detects architecture (amd64 / arm64)
# 2. Verifies TAK Server release ZIP checksum
# 3. Extracts TAK release
# 4. Generates TLS certificates via TAK certificate tools
# 5. Configures CoreConfig.xml from template
# 6. Starts TAK Server + PostgreSQL via Docker Compose
#
# ── TAK Server 5.5 gotchas ───────────────────────────────────────────────────
# CRITICAL: PostgreSQL version MUST be 15.
#   Ubuntu 24.04 defaults to PostgreSQL 16 via apt — this will cause TAK Server
#   to fail at startup. The docker-compose.yml explicitly pins postgres:15-alpine.
#
# CRITICAL: Java 17 is required.
#   TAK Server 5.5 requires Eclipse Temurin / OpenJDK 17.
#   The Dockerfiles handle this. The .deb installer additionally requires the
#   openjdk-17-jdk-headless packages to satisfy package dependencies even when
#   Temurin is the actual JRE.
#
# Reference: https://github.com/engindearing-projects/ogTAK-Server-Setup-Guides
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Colour output ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Architecture detection ─────────────────────────────────────────────────
ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)       COMPOSE_ARCH="amd64"; PLATFORM="linux/amd64";;
  aarch64|arm64) COMPOSE_ARCH="arm64"; PLATFORM="linux/arm64";;
  *)            error "Unsupported architecture: ${ARCH}";;
esac
info "Architecture: ${ARCH} → ${PLATFORM}"

# ── Locate TAK Server release ZIP ─────────────────────────────────────────
TAK_ZIP="$(ls "${REPO_DIR}"/takserver-docker-*.zip 2>/dev/null | head -1 || true)"
if [[ -z "${TAK_ZIP}" ]]; then
  error "No takserver-docker-*.zip found in ${REPO_DIR}.\nDownload from https://tak.gov/products/tak-server and place it here."
fi
TAK_BASENAME="$(basename "${TAK_ZIP}")"
info "TAK release: ${TAK_BASENAME}"

# ── Checksum verification ──────────────────────────────────────────────────
MD5_FILE="${REPO_DIR}/tak-md5checksum.txt"
SHA1_FILE="${REPO_DIR}/tak-sha1checksum.txt"

verify_checksum() {
  local file="$1" sum_file="$2" tool="$3"
  local expected
  expected="$(grep "${TAK_BASENAME}" "${sum_file}" | awk '{print $1}' || true)"
  if [[ -z "${expected}" ]]; then
    warn "No ${tool} checksum entry for ${TAK_BASENAME} in ${sum_file}. Skipping."
    return
  fi
  local actual
  actual="$(${tool}sum "${file}" | awk '{print $1}')"
  if [[ "${actual}" == "${expected}" ]]; then
    info "${tool} checksum OK: ${actual}"
  else
    error "${tool} checksum MISMATCH for ${TAK_BASENAME}.\n  Expected: ${expected}\n  Got:      ${actual}\nDo NOT proceed — release integrity cannot be verified."
  fi
}

verify_checksum "${TAK_ZIP}" "${MD5_FILE}"  "md5"
verify_checksum "${TAK_ZIP}" "${SHA1_FILE}" "sha1"

# ── Extract TAK Server ─────────────────────────────────────────────────────
TAK_DIR="${REPO_DIR}/tak"
if [[ -d "${TAK_DIR}" ]]; then
  warn "tak/ directory already exists; skipping extraction. Delete it to re-extract."
else
  info "Extracting ${TAK_BASENAME} → tak/"
  unzip -q "${TAK_ZIP}" -d "${REPO_DIR}"
  # Normalise: some releases extract to a subdirectory
  if [[ ! -f "${TAK_DIR}/takserver.war" ]]; then
    INNER="$(ls -d "${REPO_DIR}"/tak*/ 2>/dev/null | head -1 || true)"
    if [[ -n "${INNER}" ]] && [[ "${INNER}" != "${TAK_DIR}/" ]]; then
      mv "${INNER}" "${TAK_DIR}"
    fi
  fi
fi

# ── Configure CoreConfig.xml ───────────────────────────────────────────────
CONFIG_DEST="${REPO_DIR}/config/CoreConfig.xml"
if [[ ! -f "${CONFIG_DEST}" ]]; then
  info "Creating config/CoreConfig.xml from template"
  cp "${REPO_DIR}/config/CoreConfig.xml.template" "${CONFIG_DEST}"
  SERVER_ID="$(hostname)-$(date +%s)"
  sed -i "s/{{SERVER_ID}}/${SERVER_ID}/g" "${CONFIG_DEST}"
  # DB credentials (read from env or use defaults)
  TAK_DB_NAME="${TAK_DB_NAME:-cot}"
  TAK_DB_USER="${TAK_DB_USER:-martiuser}"
  TAK_DB_PASS="${TAK_DB_PASS:-$(openssl rand -hex 16)}"
  TAK_DB_HOST="${TAK_DB_HOST:-tak-db}"
  TAK_DB_PORT="${TAK_DB_PORT:-5432}"
  sed -i "s/{{TAK_DB_HOST}}/${TAK_DB_HOST}/g"   "${CONFIG_DEST}"
  sed -i "s/{{TAK_DB_PORT}}/${TAK_DB_PORT}/g"   "${CONFIG_DEST}"
  sed -i "s/{{TAK_DB_NAME}}/${TAK_DB_NAME}/g"   "${CONFIG_DEST}"
  sed -i "s/{{TAK_DB_USER}}/${TAK_DB_USER}/g"   "${CONFIG_DEST}"
  sed -i "s/{{TAK_DB_PASS}}/${TAK_DB_PASS}/g"   "${CONFIG_DEST}"
  # Write .env for docker-compose
  ENV_FILE="${REPO_DIR}/.env"
  cat > "${ENV_FILE}" <<EOF
TAK_DB_NAME=${TAK_DB_NAME}
TAK_DB_USER=${TAK_DB_USER}
TAK_DB_PASS=${TAK_DB_PASS}
EOF
  info ".env written with DB credentials"
  info ""
  info "  MAKE A NOTE OF YOUR DB PASSWORD: ${TAK_DB_PASS}"
  info "  IT WILL NOT BE SHOWN AGAIN."
  info ""
else
  info "config/CoreConfig.xml already exists; skipping template substitution."
fi

# ── Generate TLS certificates ──────────────────────────────────────────────
CERT_DIR="${REPO_DIR}/tak/certs"
if [[ ! -f "${CERT_DIR}/files/takserver.jks" ]]; then
  info "Generating TLS certificates..."
  if [[ -f "${CERT_DIR}/makeRootCa.sh" ]]; then
    pushd "${CERT_DIR}" > /dev/null
    read -rp "  Certificate authority name [tak-ca]: " CA_NAME
    CA_NAME="${CA_NAME:-tak-ca}"
    ./makeRootCa.sh --ca-name "${CA_NAME}"
    ./makeCert.sh server takserver
    read -rp "  Admin certificate name [admin]: " ADMIN_NAME
    ADMIN_NAME="${ADMIN_NAME:-admin}"
    ./makeCert.sh client "${ADMIN_NAME}"
    popd > /dev/null
    # Update CoreConfig.xml keystore passwords from generated cert env
    KEYSTORE_PASS="atakatak"
    TRUSTSTORE_PASS="atakatak"
    sed -i "s/{{KEYSTORE_PASS}}/${KEYSTORE_PASS}/g"     "${CONFIG_DEST}"
    sed -i "s/{{TRUSTSTORE_PASS}}/${TRUSTSTORE_PASS}/g" "${CONFIG_DEST}"
    info "Certificates generated in tak/certs/files/"
  else
    warn "Certificate scripts not found in tak/certs/. You may need to run cert generation manually."
    sed -i "s/{{KEYSTORE_PASS}}/atakatak/g"     "${CONFIG_DEST}"
    sed -i "s/{{TRUSTSTORE_PASS}}/atakatak/g"   "${CONFIG_DEST}"
  fi
else
  info "Certificates already exist; skipping."
fi

# ── Network interface selection ────────────────────────────────────────────
info ""
info "Available network interfaces:"
INTERFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v "^lo$"))
select NIC in "${INTERFACES[@]}"; do
  if [[ -n "${NIC}" ]]; then
    SERVER_IP="$(ip -4 addr show "${NIC}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || true)"
    if [[ -z "${SERVER_IP}" ]]; then
      warn "No IPv4 address on ${NIC}; proceeding anyway."
    else
      info "TAK Server will be accessible at: ${SERVER_IP}:8443"
    fi
    break
  fi
done

# ── Start services ────────────────────────────────────────────────────────
info "Starting TAK Server via Docker Compose..."
COMPOSE_CMD=(docker compose)
if [[ "${COMPOSE_ARCH}" == "arm64" ]]; then
  info "Using ARM64 compose overrides (docker-compose.arm64.yml)"
  COMPOSE_CMD+=(- f docker-compose.yml -f docker-compose.arm64.yml)
fi

cd "${REPO_DIR}"
"${COMPOSE_CMD[@]}" up -d

info ""
info "TAK Server is starting. Web UI: https://${SERVER_IP:-localhost}:8443"
info "Import tak/certs/files/${ADMIN_NAME:-admin}.p12 into your browser (password: atakatak)"
info ""
info "To view logs: docker compose logs -f tak-server"
