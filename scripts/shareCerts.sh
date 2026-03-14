#!/usr/bin/env bash
# Share client certificate data packages over a local HTTP server (port 12345).
# Only run on a TRUSTED network — no TLS.
#
# Usage: ./scripts/shareCerts.sh

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARE_DIR="${REPO_DIR}/tak/certs/files"

if [[ ! -d "${SHARE_DIR}" ]]; then
  echo "ERROR: ${SHARE_DIR} not found. Run setup.sh first." >&2
  exit 1
fi

echo "Serving cert packages from ${SHARE_DIR} on port 12345"
echo "WARNING: This is unencrypted. Only use on a trusted network."
echo "Press Ctrl-C to stop."
cd "${SHARE_DIR}"
python3 -m http.server 12345
