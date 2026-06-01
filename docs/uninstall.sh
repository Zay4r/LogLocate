#!/usr/bin/env bash
# uninstall.sh — loglo full uninstaller
#
# Removes: all systemd services, binaries, config, APT repo, GPG key,
#          and ALL .idx / .batch / .cooldown / .flush index files.
#
# One-liner:
#   curl -fsSL https://zay4r.github.io/LogLocate/uninstall.sh | sudo bash
#
# Local:
#   sudo bash uninstall.sh

set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
BLU='\033[0;34m'
YLW='\033[1;33m'
RST='\033[0m'

# ─── Must run as root ─────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run as root:${RST}" >&2
  echo -e "${RED}  curl -fsSL https://zay4r.github.io/LogLocate/uninstall.sh | sudo bash${RST}" >&2
  exit 1
fi

echo -e "${BLU}Uninstalling loglo — full cleanup...${RST}"
echo ""

# ─── Collect index file paths BEFORE removing the registry ───────────────────
# Read watched paths from registry now so we can delete their .idx files later.
REGISTRY="/etc/log-locate/registry"
declare -a WATCHED_PATHS=()
if [[ -f "$REGISTRY" ]]; then
  while IFS=$'\t' read -r _name abs_file; do
    [[ -z "$abs_file" ]] && continue
    WATCHED_PATHS+=("$abs_file")
  done < "$REGISTRY"
fi

# ─── Stop and disable all loglo systemd services ─────────────────────────────
echo "  Stopping all loglo services..."
# list-units catches currently loaded units (running or failed)
while IFS= read -r unit; do
  [[ -z "$unit" ]] && continue
  echo "    stopping : $unit"
  systemctl stop    "$unit" 2>/dev/null || true
  systemctl disable "$unit" 2>/dev/null || true
done < <(systemctl list-units --type=service --all --no-legend \
  | awk '{print $1}' \
  | grep -E '^(loglo-|log-locate[@_])' || true)

# Also stop any units found only in list-unit-files (not yet loaded)
while IFS= read -r unit; do
  [[ -z "$unit" ]] && continue
  systemctl stop    "$unit" 2>/dev/null || true
  systemctl disable "$unit" 2>/dev/null || true
done < <(systemctl list-unit-files --type=service --no-legend \
  | awk '{print $1}' \
  | grep -E '^(loglo-|log-locate[@_])' || true)

# Remove all service unit files
shopt -s nullglob
SERVICE_FILES=(
  /etc/systemd/system/loglo-*.service
  /etc/systemd/system/log-locate@*.service
  /etc/systemd/system/log-locate_.service
)
for f in "${SERVICE_FILES[@]}"; do
  echo "    removed  : $f"
  rm -f "$f"
done
shopt -u nullglob

systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true
echo -e "  ${GRN}✓ Services removed.${RST}"

# ─── Remove APT package (if installed via apt) ────────────────────────────────
if dpkg -s loglo &>/dev/null 2>&1; then
  echo "  Removing apt package loglo..."
  apt-get remove -y loglo 2>/dev/null || true
  apt-get purge  -y loglo 2>/dev/null || true
  echo -e "  ${GRN}✓ APT package removed.${RST}"
fi

# ─── Remove APT repo and GPG key ─────────────────────────────────────────────
echo "  Removing APT repository..."
rm -f /etc/apt/sources.list.d/loglo.list
rm -f /etc/apt/keyrings/loglo.gpg
# Also handle legacy /etc/apt/trusted.gpg.d/ location
rm -f /etc/apt/trusted.gpg.d/loglo.gpg
apt-get update -qq 2>/dev/null || true
echo -e "  ${GRN}✓ APT repo and GPG key removed.${RST}"

# ─── Remove binaries ──────────────────────────────────────────────────────────
echo "  Removing binaries..."
for f in \
  /usr/local/bin/log-locate \
  /usr/local/bin/log-locate-daemon \
  /usr/local/bin/loglo; do
  [[ -e "$f" || -L "$f" ]] && { rm -f "$f"; echo "    removed  : $f"; }
done
echo -e "  ${GRN}✓ Binaries removed.${RST}"

# ─── Remove config directory ──────────────────────────────────────────────────
echo "  Removing /etc/log-locate..."
rm -rf /etc/log-locate
echo -e "  ${GRN}✓ Config removed.${RST}"

# ─── Remove index/temp files next to watched log files ───────────────────────
echo "  Removing index files from watched paths..."
IDX_COUNT=0
for abs_file in "${WATCHED_PATHS[@]}"; do
  for ext in .idx .batch .cooldown .flush; do
    target="${abs_file}${ext}"
    if [[ -f "$target" ]]; then
      rm -f "$target"
      echo "    removed  : $target"
      IDX_COUNT=$(( IDX_COUNT + 1 ))
    fi
  done
done

# Safety net: scan common log directories for any leftover index files
# (catches files from paths not in registry, or registry already deleted)
echo "  Scanning for any remaining index files..."
while IFS= read -r f; do
  rm -f "$f"
  echo "    removed  : $f"
  IDX_COUNT=$(( IDX_COUNT + 1 ))
done < <(find /var/log /home /root /etc /opt /srv /tmp \
  -maxdepth 8 \
  \( -name '*.log.idx' \
  -o -name '*.log.batch' \
  -o -name '*.log.cooldown' \
  -o -name '*.log.flush' \) \
  2>/dev/null || true)

if [[ $IDX_COUNT -gt 0 ]]; then
  echo -e "  ${GRN}✓ Removed $IDX_COUNT index/temp file(s).${RST}"
else
  echo "    none found."
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "${GRN}  loglo fully uninstalled. Nothing left behind.${RST}"
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo "To reinstall:"
echo "  curl -fsSL https://zay4r.github.io/LogLocate/setup.sh | sudo bash"
echo ""