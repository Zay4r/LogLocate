#!/usr/bin/env bash
# install.sh — log-locate installer
#
# Installs binaries as /usr/local/bin/log-locate and /usr/local/bin/log-locate-daemon.
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
_get_file "log-locate"        "${BIN_DIR}/log-locate"
_get_file "log-locate-daemon" "${BIN_DIR}/log-locate-daemon"

chmod +x "${BIN_DIR}/log-locate"
chmod +x "${BIN_DIR}/log-locate-daemon"

# loglo is just a convenience symlink → log-locate
ln -sf "${BIN_DIR}/log-locate" "${BIN_DIR}/loglo"

echo "  Installed: ${BIN_DIR}/log-locate"
echo "  Installed: ${BIN_DIR}/log-locate-daemon"
echo "  Symlink  : ${BIN_DIR}/loglo → ${BIN_DIR}/log-locate"

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

# ─── Telegram setup prompts ───────────────────────────────────────────────────
echo ""
echo -e "${BLU}━━━  Telegram Alert Setup  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
echo "  log-locate can send alerts to a Telegram chat."
echo "  Leave blank to skip and configure manually later in /etc/log-locate/config"
echo ""

# When piped through curl | bash, stdin is the pipe — read must use /dev/tty directly.
# Declare first so -u never sees an unbound variable even if read fails.
tg_token=""
tg_chat=""
_read_tty() {
  local __var="$1" __prompt="$2" __val=""
  # Write prompt directly to /dev/tty so it shows even when stdout is a pipe
  printf '%s' "$__prompt" >/dev/tty
  { read -r __val </dev/tty; } 2>/dev/null || true
  printf -v "$__var" '%s' "${__val:-}"
}
if [[ -e /dev/tty ]]; then
  _read_tty tg_token "  Enter TELEGRAM_BOT_TOKEN (or press Enter to skip): "
  _read_tty tg_chat  "  Enter TELEGRAM_CHAT_ID   (or press Enter to skip): "
fi

if [[ -n "$tg_token" || -n "$tg_chat" ]]; then
  CONFIG_FILE="${CONFIG_DIR}/config"
  # Replace token line
  if [[ -n "$tg_token" ]]; then
    sed -i "s|^TELEGRAM_BOT_TOKEN=.*|TELEGRAM_BOT_TOKEN=\"${tg_token}\"|" "$CONFIG_FILE"
    echo -e "  ${GRN}✓ TELEGRAM_BOT_TOKEN saved.${RST}"
  fi
  # Replace chat id line
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
echo "  3. Search the index:"
echo "     loglo search /home/deved/vpn-server/logs/server.log \"user_id=87904\""
echo ""
echo "  4. Range search:"
echo "     loglo range /home/deved/vpn-server/logs/server.log 2026-05-28T10:15:00Z 2026-05-28T10:20:00Z"
echo ""
echo "  5. View all watched files:"
echo "     loglo status"
echo ""