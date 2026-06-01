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
# Run apt with stdin explicitly from /dev/tty so our later prompts aren't
# contaminated by the pipe, and apt's own interactive output goes to the tty.
apt-get install -y loglo </dev/tty

# ─── Telegram setup (must run here, AFTER apt exits — not inside postinst) ───
# When piped through curl | bash, stdin is the pipe, so we read via /dev/tty.
CONFIG_FILE="/etc/log-locate/config"

echo ""
echo -e "${BLU}━━━  Telegram Alert Setup  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo "  loglo can send alerts to a Telegram chat."
echo "  Leave blank to skip — edit /etc/log-locate/config to configure later."
echo ""

tg_token=""
tg_chat=""

_read_tty() {
  local __var="$1" __prompt="$2" __val=""
  printf '%s' "$__prompt" >/dev/tty
  # Disable bracket-paste mode so terminal escape sequences don't leak in,
  # then re-enable it when done.
  printf '\e[?2004l' >/dev/tty
  { IFS= read -r __val </dev/tty; } 2>/dev/null || true
  printf '\e[?2004h' >/dev/tty
  # Strip any stray escape/bracket-paste sequences that slipped through
  __val=$(printf '%s' "$__val" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\[200~//g; s/~$//g')
  printf -v "$__var" '%s' "${__val:-}"
}

if [[ -e /dev/tty ]]; then
  _read_tty tg_token "  Enter TELEGRAM_BOT_TOKEN (or press Enter to skip): "
  _read_tty tg_chat  "  Enter TELEGRAM_CHAT_ID   (or press Enter to skip): "
fi

if [[ -n "$tg_token" || -n "$tg_chat" ]]; then
  if [[ -n "$tg_token" ]]; then
    sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=\"${tg_token}\"|" "$CONFIG_FILE"
    echo -e "  ${GRN}✓ TELEGRAM_BOT_TOKEN saved.${RST}"
  fi
  if [[ -n "$tg_chat" ]]; then
    sed -i "s|^TELEGRAM_CHAT_ID=.*|TELEGRAM_CHAT_ID=\"${tg_chat}\"|" "$CONFIG_FILE"
    echo -e "  ${GRN}✓ TELEGRAM_CHAT_ID saved.${RST}"
  fi
else
  echo "  Skipped — edit /etc/log-locate/config to add credentials later."
fi
echo -e "${BLU}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo -e "${GRN}  loglo installed! Future updates: sudo apt upgrade${RST}"
echo -e "${GRN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo ""
echo "Next steps:"
echo ""
echo "  Start watching a log file:"
echo "    sudo loglo add /var/log/myapp/server.log"
echo ""
echo "  Search:"
echo "    loglo search server \"ERROR\""
echo ""
echo "  Status:"
echo "    loglo status"
echo ""