#!/usr/bin/env bash
# setup.sh — loglo one-line installer
#
# Usage:
#   curl -fsSL https://zay4r.github.io/LogLocate/setup.sh | sudo bash

set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
BLU='\033[0;34m'
YLW='\033[1;33m'
RST='\033[0m'

REPO_URL="https://zay4r.github.io/LogLocate"
KEYRING="/etc/apt/keyrings/loglo.gpg"
SOURCES="/etc/apt/sources.list.d/loglo.list"

# ─── Must run as root ─────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run as root:${RST}" >&2
  echo -e "${RED}  curl -fsSL ${REPO_URL}/setup.sh | sudo bash${RST}" >&2
  exit 1
fi

# ─── Check dependencies ───────────────────────────────────────────────────────
for dep in curl gpg apt-get; do
  if ! command -v "$dep" &>/dev/null; then
    echo -e "${RED}Missing dependency: $dep${RST}" >&2
    exit 1
  fi
done

echo -e "${BLU}"
echo "  ██╗      ██████╗  ██████╗ ██╗      ██████╗ "
echo "  ██║     ██╔═══██╗██╔════╝ ██║     ██╔═══██╗"
echo "  ██║     ██║   ██║██║  ███╗██║     ██║   ██║"
echo "  ██║     ██║   ██║██║   ██║██║     ██║   ██║"
echo "  ███████╗╚██████╔╝╚██████╔╝███████╗╚██████╔╝"
echo "  ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝ ╚═════╝ "
echo -e "${RST}"
echo -e "${BLU}  Log indexer and alerter — github.com/Zay4r/LogLocate${RST}"
echo ""

# ─── Add GPG key ──────────────────────────────────────────────────────────────
echo "  Adding GPG key..."
mkdir -p /etc/apt/keyrings
curl -fsSL "${REPO_URL}/KEY.gpg" | gpg --dearmor -o "$KEYRING"
chmod 644 "$KEYRING"
echo -e "  ${GRN}✓ GPG key added.${RST}"

# ─── Add APT source ───────────────────────────────────────────────────────────
echo "  Adding APT repository..."
echo "deb [arch=all signed-by=${KEYRING}] ${REPO_URL} stable main" > "$SOURCES"
echo -e "  ${GRN}✓ Repository added.${RST}"

# ─── apt update ───────────────────────────────────────────────────────────────
echo "  Running apt update..."
apt-get update -qq
echo -e "  ${GRN}✓ Package list updated.${RST}"

# ─── apt install ──────────────────────────────────────────────────────────────
echo "  Installing loglo..."
echo ""
apt-get install -y loglo

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "${GRN}  loglo installed! Future updates: sudo apt upgrade${RST}"
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""