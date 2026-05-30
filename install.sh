#!/usr/bin/env bash
# install.sh — loglo installer
#
# Usage (remote):
#   curl -fsSL https://raw.githubusercontent.com/Zay4r/LogLocate/main/install.sh | sudo bash
#
# Usage (local):
#   sudo bash install.sh

set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
BLU='\033[0;34m'
RST='\033[0m'

BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/log-locate"
SERVICE_DIR="/etc/systemd/system"
REPO_RAW="https://raw.githubusercontent.com/Zay4r/LogLocate/main"

# ─── Must run as root ─────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run as root: sudo bash install.sh${RST}" >&2
  exit 1
fi

echo -e "${BLU}Installing loglo...${RST}"

# ─── Check dependencies ───────────────────────────────────────────────────────
for dep in curl tail awk grep dd systemctl; do
  if ! command -v "$dep" &>/dev/null; then
    echo -e "${RED}Missing dependency: $dep${RST}" >&2
    exit 1
  fi
done

# ─── Detect: running locally or piped from curl ──────────────────────────────
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" && -f "$(dirname "${BASH_SOURCE[0]}")/log-locate" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  USE_LOCAL=true
else
  SCRIPT_DIR=""
  USE_LOCAL=false
fi

_get_file() {
  local name="$1"
  local dest="$2"
  if $USE_LOCAL && [[ -f "${SCRIPT_DIR}/${name}" ]]; then
    echo "  (local) $name"
    cp "${SCRIPT_DIR}/${name}" "$dest"
  else
    echo "  (download) $name"
    curl -fsSL "${REPO_RAW}/${name}" -o "$dest"
  fi
}

# ─── Install binaries ─────────────────────────────────────────────────────────
echo "  Installing binaries..."
_get_file "log-locate"        "${BIN_DIR}/loglo"
_get_file "log-locate-daemon" "${BIN_DIR}/loglo-daemon"

chmod +x "${BIN_DIR}/loglo"
chmod +x "${BIN_DIR}/loglo-daemon"

echo "  Installed: ${BIN_DIR}/loglo"
echo "  Installed: ${BIN_DIR}/loglo-daemon"

# ─── Install systemd service ──────────────────────────────────────────────────
echo "  Installing systemd service..."
_get_file "log-locate@.service" "${SERVICE_DIR}/log-locate@.service"
systemctl daemon-reload
echo "  Installed: ${SERVICE_DIR}/log-locate@.service"

# ─── Write default config (don't overwrite existing) ─────────────────────────
mkdir -p "$CONFIG_DIR"
if [[ ! -f "${CONFIG_DIR}/config" ]]; then
  echo "  Writing default config..."
  _get_file "config" "${CONFIG_DIR}/config"
  echo "  Config   : ${CONFIG_DIR}/config"
else
  echo "  Config already exists — skipping: ${CONFIG_DIR}/config"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}loglo installed successfully!${RST}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Edit the config:"
echo "     nano /etc/log-locate/config"
echo ""
echo "  2. Start watching a log file:"
echo "     sudo loglo add /home/deved/vpn-server/logs/server.log"
echo ""
echo "  3. Search the index:"
echo "     loglo search /home/deved/vpn-server/logs/server.log \"user_id=87904\""
echo ""
echo "  4. Range search:"
echo "     loglo range /home/deved/vpn-server/logs/server.log 2026-05-28T10:15:00Z 2026-05-28T10:20:00Z"
echo ""
echo "  5. View all watched files:"
echo "     loglo status"
echo ""
