#!/usr/bin/env bash
# uninstall.sh — loglo uninstaller
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

# ─── Must run as root ─────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run as root: sudo bash uninstall.sh${RST}" >&2
  exit 1
fi

echo -e "${BLU}Uninstalling loglo...${RST}"

# ─── Stop and disable all running instances ───────────────────────────────────
echo "  Stopping all loglo services..."
while IFS= read -r unit; do
  [[ -z "$unit" ]] && continue
  echo "  Stopping: $unit"
  systemctl stop    "$unit" 2>/dev/null || true
  systemctl disable "$unit" 2>/dev/null || true
done < <(systemctl list-units --type=service --all \
  | grep 'log-locate@' \
  | awk '{print $1}')

# ─── Remove binaries ──────────────────────────────────────────────────────────
echo "  Removing binaries..."
rm -f /usr/local/bin/loglo
rm -f /usr/local/bin/loglo-daemon
echo "  Removed: /usr/local/bin/loglo"
echo "  Removed: /usr/local/bin/loglo-daemon"

# ─── Remove systemd service ───────────────────────────────────────────────────
echo "  Removing systemd service..."
rm -f /etc/systemd/system/log-locate@.service
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true
echo "  Removed: /etc/systemd/system/log-locate@.service"

# ─── Remove config directory ──────────────────────────────────────────────────
echo "  Removing config..."
rm -rf /etc/log-locate
echo "  Removed: /etc/log-locate"

# ─── Ask about index files ────────────────────────────────────────────────────
echo ""
echo -e "${YLW}Index files (.idx, .batch, .cooldown) are left next to your log files.${RST}"
echo -e "${YLW}Remove them manually if you no longer need them:${RST}"
echo ""
echo "  find / -name '*.log.idx' 2>/dev/null"
echo "  find / -name '*.log.batch' 2>/dev/null"
echo ""

# ─── Done ─────────────────────────────────────────────────────────────────────
echo -e "${GRN}loglo uninstalled successfully.${RST}"
echo ""
echo "To reinstall:"
echo "  curl -fsSL https://raw.githubusercontent.com/Zay4r/LogLocate/main/install.sh | sudo bash"
echo ""
