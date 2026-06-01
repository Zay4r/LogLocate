#!/usr/bin/env bash
# install.sh — log-locate installer
#
# Installs binary as /usr/local/bin/log-locate-daemon.
# Creates /usr/local/bin/loglo as a symlink alias for faster typing.
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

echo -e "${BLU}Installing log-locate...${RST}"

# ─── Check dependencies ───────────────────────────────────────────────────────
for dep in curl tail awk grep systemctl; do
  if ! command -v "$dep" &>/dev/null; then
    echo -e "${RED}Missing dependency: $dep${RST}" >&2
    exit 1
  fi
done

# ─── Detect: running locally or piped from curl ──────────────────────────────
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" && -f "$(dirname "${BASH_SOURCE[0]}")/log-locate-daemon" ]]; then
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

# ─── Install binary ───────────────────────────────────────────────────────────
echo "  Installing binary..."
_get_file "log-locate-daemon" "${BIN_DIR}/log-locate-daemon"
chmod +x "${BIN_DIR}/log-locate-daemon"

# loglo is a convenience symlink → log-locate-daemon
ln -sf "${BIN_DIR}/log-locate-daemon" "${BIN_DIR}/loglo"

echo "  Installed: ${BIN_DIR}/log-locate-daemon"
echo "  Symlink  : ${BIN_DIR}/loglo → ${BIN_DIR}/log-locate-daemon"

# ─── Install systemd service template ────────────────────────────────────────
echo "  Installing systemd service template..."
_get_file "log-locate_.service" "${SERVICE_DIR}/log-locate_.service"
systemctl daemon-reload
echo "  Installed: ${SERVICE_DIR}/log-locate_.service"

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
echo "     sudo loglo add /home/deved/vpn-server/logs/server.log"
echo ""
echo "  3. View all watched files:"
echo "     loglo status"
echo ""
