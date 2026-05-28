#!/usr/bin/env bash
# install.sh — log-locate installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/you/log-locate/main/install.sh | sudo bash
#
# Or locally:
#   sudo bash install.sh

set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
BLU='\033[0;34m'
RST='\033[0m'

BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/log-locate"
SERVICE_DIR="/etc/systemd/system"
REPO_RAW="https://raw.githubusercontent.com/you/log-locate/main"

# ─── Must run as root ─────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run as root: sudo bash install.sh${RST}" >&2
  exit 1
fi

echo -e "${BLU}Installing log-locate...${RST}"

# ─── Check dependencies ───────────────────────────────────────────────────────
for dep in curl tail awk grep dd systemctl; do
  if ! command -v "$dep" &>/dev/null; then
    echo -e "${RED}Missing dependency: $dep${RST}" >&2
    exit 1
  fi
done

# ─── Detect: running from local dir or downloading from GitHub ───────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_get_file() {
  local name="$1"
  local dest="$2"
  if [[ -f "${SCRIPT_DIR}/${name}" ]]; then
    # Local install
    cp "${SCRIPT_DIR}/${name}" "$dest"
  else
    # Remote install
    curl -fsSL "${REPO_RAW}/${name}" -o "$dest"
  fi
}

# ─── Install binaries ─────────────────────────────────────────────────────────
echo "  Installing binaries..."
_get_file "log-locate"        "${BIN_DIR}/log-locate"
_get_file "log-locate-daemon" "${BIN_DIR}/log-locate-daemon"

chmod +x "${BIN_DIR}/log-locate"
chmod +x "${BIN_DIR}/log-locate-daemon"

echo "  Installed: ${BIN_DIR}/log-locate"
echo "  Installed: ${BIN_DIR}/log-locate-daemon"

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
echo -e "${GRN}log-locate installed successfully!${RST}"
echo ""
echo "Next steps:"
echo ""
echo "  1. Edit the config:"
echo "     nano /etc/log-locate/config"
echo ""
echo "  2. Start watching a log file:"
echo "     sudo log-locate add /etc/project/logs/app.log"
echo ""
echo "  3. Search the index:"
echo "     log-locate search /etc/project/logs/app.log \"user_id=87904\""
echo ""
echo "  4. Range search:"
echo "     log-locate range /etc/project/logs/app.log 2026-05-28T10:15:00Z 2026-05-28T10:20:00Z"
echo ""
echo "  5. View all watched files:"
echo "     log-locate status"
echo ""
