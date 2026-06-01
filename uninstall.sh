#!/usr/bin/env bash
# uninstall.sh — log-locate uninstaller
#
# Usage (remote):
#   curl -fsSL https://raw.githubusercontent.com/Zay4r/LogLocate/main/uninstall.sh | sudo bash
#
# Usage (local):
#   sudo bash uninstall.sh

set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
BLU='\033[0;34m'
YLW='\033[1;33m'
RST='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run as root: sudo bash uninstall.sh${RST}" >&2
  exit 1
fi

echo -e "${BLU}Uninstalling log-locate...${RST}"

# ─── Stop and disable all running instances ───────────────────────────────────
echo "  Stopping all log-locate services..."
while IFS= read -r unit; do
  [[ -z "$unit" ]] && continue
  echo "  Stopping: $unit"
  systemctl stop    "$unit" 2>/dev/null || true
  systemctl disable "$unit" 2>/dev/null || true
  rm -f "/etc/systemd/system/${unit}"
done < <(systemctl list-units --type=service --all --no-legend \
  | awk '{print $1}' \
  | grep '^log-locate@')

rm -f /etc/systemd/system/log-locate@.service
rm -f /etc/systemd/system/log-locate_.service

# ─── Remove binaries ──────────────────────────────────────────────────────────
echo "  Removing binaries..."
rm -f /usr/local/bin/log-locate-daemon
rm -f /usr/local/bin/loglo
echo "  Removed: /usr/local/bin/log-locate-daemon"
echo "  Removed: /usr/local/bin/loglo"

# ─── Reload systemd ───────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# ─── Remove config directory ──────────────────────────────────────────────────
echo "  Removing config..."
rm -rf /etc/log-locate
echo "  Removed: /etc/log-locate"

echo ""
echo -e "${GRN}log-locate uninstalled successfully.${RST}"
echo ""
echo "To reinstall:"
echo "  curl -fsSL https://raw.githubusercontent.com/Zay4r/LogLocate/main/install.sh | sudo bash"
echo ""