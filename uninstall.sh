#!/usr/bin/env bash
# uninstall.sh — log-locate uninstaller
#
# Usage (remote):
#   curl -fsSL https://raw.githubusercontent.com/Zay4r/LogLocate/v2/uninstall.sh -o /tmp/uninstall.sh && sudo bash /tmp/uninstall.sh
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

REGISTRY="/etc/log-locate/registry"
SERVICE_DIR="/etc/systemd/system"

# ─── Remove sidecar files for each registered log ────────────────────────────
# Do this first, while we still have the registry to look up paths.
if [[ -f "$REGISTRY" ]]; then
  echo "  Cleaning up index and state files..."
  while IFS=$'\t' read -r name abs_file; do
    [[ -z "$abs_file" ]] && continue
    for ext in idx batch cooldown flush; do
      if [[ -f "${abs_file}.${ext}" ]]; then
        rm -f "${abs_file}.${ext}"
        echo "  Removed: ${abs_file}.${ext}"
      fi
    done
  done < "$REGISTRY"
fi

# ─── Stop and disable all loglo-* per-file services (current naming) ─────────
echo "  Stopping all loglo-* services..."
FOUND_LOGLO=0
while IFS= read -r unit; do
  [[ -z "$unit" ]] && continue
  echo "  Stopping: $unit"
  systemctl stop    "$unit" 2>/dev/null || true
  systemctl disable "$unit" 2>/dev/null || true
  FOUND_LOGLO=1
done < <(systemctl list-units --type=service --all --no-legend \
  | awk '{print $1}' \
  | grep '^loglo-' || true)
[[ $FOUND_LOGLO -eq 0 ]] && echo "  (none active)"

# ─── Stop and disable legacy log-locate@ template instances ──────────────────
echo "  Stopping any legacy log-locate@ instances..."
FOUND_LEGACY=0
while IFS= read -r unit; do
  [[ -z "$unit" ]] && continue
  echo "  Stopping: $unit"
  systemctl stop    "$unit" 2>/dev/null || true
  systemctl disable "$unit" 2>/dev/null || true
  FOUND_LEGACY=1
done < <(systemctl list-units --type=service --all --no-legend \
  | awk '{print $1}' \
  | grep '^log-locate@' || true)
[[ $FOUND_LEGACY -eq 0 ]] && echo "  (none active)"

# ─── Remove all loglo-*.service unit files from disk ─────────────────────────
echo "  Removing service unit files..."
for f in "${SERVICE_DIR}"/loglo-*.service; do
  [[ -f "$f" ]] || continue
  rm -f "$f"
  echo "  Removed: $f"
done

# ─── Remove template service files ───────────────────────────────────────────
rm -f "${SERVICE_DIR}/log-locate@.service"  && echo "  Removed: ${SERVICE_DIR}/log-locate@.service"  || true
rm -f "${SERVICE_DIR}/log-locate_.service"  && echo "  Removed: ${SERVICE_DIR}/log-locate_.service"  || true

# ─── Reload systemd ───────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# ─── Remove binaries ──────────────────────────────────────────────────────────
echo "  Removing binaries..."
rm -f /usr/local/bin/log-locate-daemon  && echo "  Removed: /usr/local/bin/log-locate-daemon"  || true
rm -f /usr/local/bin/loglo              && echo "  Removed: /usr/local/bin/loglo"              || true
rm -f /usr/local/bin/log-locate         && echo "  Removed: /usr/local/bin/log-locate"         || true

# ─── Remove config directory (registry, configs, global config) ───────────────
echo "  Removing config..."
rm -rf /etc/log-locate
echo "  Removed: /etc/log-locate"

# ─── Remove runtime directory ────────────────────────────────────────────────
rm -rf /run/log-locate 2>/dev/null && echo "  Removed: /run/log-locate" || true

# ─── Remove system user ───────────────────────────────────────────────────────
if id -u log-locate &>/dev/null; then
  userdel log-locate 2>/dev/null || true
  echo "  Removed system user: log-locate"
fi

echo ""
echo -e "${GRN}log-locate uninstalled successfully.${RST}"
echo ""
echo "To reinstall:"
echo "  curl -fsSL https://raw.githubusercontent.com/Zay4r/LogLocate/v2/install.sh -o /tmp/install.sh && sudo bash /tmp/install.sh"
echo ""