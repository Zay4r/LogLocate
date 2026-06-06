#!/usr/bin/env bash
# install.sh — log-locate installer
#
# Installs:
#   /usr/local/bin/log-locate-daemon  — file watcher/alerter daemon
#   /usr/local/bin/loglo              — CLI (add / remove / status / logs / test-alert)
#   /etc/systemd/system/log-locate@.service
#   /etc/log-locate/config            — written via interactive wizard
#
# Usage (remote):
#   curl -fsSL https://raw.githubusercontent.com/Zay4r/LogLocate/v2/install.sh | sudo bash
#
# Usage (local):
#   sudo bash install.sh

set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
DIM='\033[2m'
RST='\033[0m'

BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/log-locate"
SERVICE_DIR="/etc/systemd/system"
REPO_RAW="https://raw.githubusercontent.com/Zay4r/LogLocate/v2"

# ─── Must run as root ─────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run as root: sudo bash install.sh${RST}" >&2
  exit 1
fi

# ─── Re-attach stdin to terminal immediately ──────────────────────────────────
# When piped from curl, stdin is the pipe. Redirect to /dev/tty now — before
# any downloads — so the wizard's read calls work without any lag or race.
if [[ -t 0 ]]; then
  : # already a terminal, stdin is fine
elif [[ -r /dev/tty && -w /dev/tty ]]; then
  exec </dev/tty
else
  echo -e "${YLW}Warning: no TTY available — whiptail wizard may not render.${RST}"
  echo -e "${YLW}Tip: download the script and run it directly instead of piping from curl.${RST}"
fi

echo -e "${BLU}Installing log-locate...${RST}"

# ─── Check dependencies ───────────────────────────────────────────────────────
for dep in curl tail awk grep systemctl systemd-escape; do
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
  local name="$1" dest="$2"
  if $USE_LOCAL && [[ -f "${SCRIPT_DIR}/${name}" ]]; then
    echo "  (local) $name"
    cp "${SCRIPT_DIR}/${name}" "$dest"
  else
    echo "  (download) $name"
    curl -fsSL "${REPO_RAW}/${name}" -o "$dest"
  fi
}

# ─── Create system user ───────────────────────────────────────────────────────
if ! id -u log-locate &>/dev/null; then
  echo "  Creating system user: log-locate"
  useradd --system --no-create-home --shell /usr/sbin/nologin log-locate
  echo "  Created user: log-locate"
else
  echo "  System user already exists: log-locate"
fi

# ─── Install daemon binary ────────────────────────────────────────────────────
echo "  Installing daemon..."
_get_file "log-locate-daemon" "${BIN_DIR}/log-locate-daemon"
chmod +x "${BIN_DIR}/log-locate-daemon"
echo "  Installed: ${BIN_DIR}/log-locate-daemon"

# ─── Install loglo CLI ────────────────────────────────────────────────────────
echo "  Installing loglo CLI..."
_get_file "log-locate" "${BIN_DIR}/loglo"
chmod +x "${BIN_DIR}/loglo"
# Also install as log-locate for direct invocation
cp "${BIN_DIR}/loglo" "${BIN_DIR}/log-locate"
chmod +x "${BIN_DIR}/log-locate"
echo "  Installed: ${BIN_DIR}/loglo"
echo "  Installed: ${BIN_DIR}/log-locate"

# ─── Install systemd service template ────────────────────────────────────────
echo "  Installing systemd service template..."
_get_file "log-locate_.service" "${SERVICE_DIR}/log-locate@.service"
systemctl daemon-reload
echo "  Installed: ${SERVICE_DIR}/log-locate@.service"

# ─── Interactive config wizard (TUI) ──────────────────────────────────────────
mkdir -p "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"
chown root:root "$CONFIG_DIR"

# Ensure whiptail is available for the TUI wizard
if ! command -v whiptail &>/dev/null; then
  echo "  Installing whiptail for interactive setup UI..."
  if command -v apt-get &>/dev/null; then
    echo "  Running apt-get update (this may take a moment)..."
apt-get update -qq && apt-get install -y -qq whiptail
  elif command -v yum &>/dev/null; then
    yum install -y -q whiptail >/dev/null
  fi
fi

CONFIG_EXISTS=false
[[ -f "${CONFIG_DIR}/config" ]] && CONFIG_EXISTS=true

if $CONFIG_EXISTS; then
  if ! whiptail --title "Config Exists" --yesno "Configuration already exists at ${CONFIG_DIR}/config\n\nDo you want to re-run the setup wizard and overwrite it?" 10 60; then
    echo "  Skipping — keeping existing config."
    CONFIG_DONE=true
  fi
fi

if [[ "${CONFIG_DONE:-false}" != "true" ]]; then
  
  # 1. Choose Notification Channel
  NOTIFY=$(whiptail --title "Log-Locate Setup Wizard" --menu \
    "Select your primary notification alert backend:" 12 60 3 \
    "telegram" "Send structured raw snippets to a Telegram Chat" \
    "email"    "Send email via custom SMTP connection" \
    "both"     "Dispatch alerts via Telegram AND Email simultaneously" \
    3>&1 1>&2 2>&3) || NOTIFY="telegram"

  # 2. Alert Patterns
  ALERT_PATTERNS=$(whiptail --title "Alert Configurations" --inputbox \
    "Specify words/patterns that trigger alerts (space-separated):\n\nPrefix wildcards are supported (e.g. user_id=*)" \
    12 60 "ERROR FATAL WARN" 3>&1 1>&2 2>&3) || ALERT_PATTERNS="ERROR FATAL WARN"

  # 3. Batching Timeline
  BATCH_SECONDS=$(whiptail --title "Performance Parameters" --inputbox \
    "Batch window (seconds):\nHow long should logs accumulate before sending a grouped alert summary?" \
    12 60 "10" 3>&1 1>&2 2>&3) || BATCH_SECONDS="10"

  # 4. Cooldown Period
  COOLDOWN_SECONDS=$(whiptail --title "Performance Parameters" --inputbox \
    "Cooldown window (seconds):\nHow long should notifications be suppressed after an alert finishes firing?" \
    12 60 "300" 3>&1 1>&2 2>&3) || COOLDOWN_SECONDS="300"

  # Initialize variable spaces
  TELEGRAM_BOT_TOKEN=""
  TELEGRAM_CHAT_ID=""
  SMTP_HOST="smtp.gmail.com"
  SMTP_PORT="587"
  SMTP_USER=""
  SMTP_PASS=""
  ALERT_FROM=""
  ALERT_TO=""

  # 5. Conditional Telegram Setup
  if [[ "$NOTIFY" == "telegram" || "$NOTIFY" == "both" ]]; then
    TELEGRAM_BOT_TOKEN=$(whiptail --title "Telegram Bot API Settings" --passwordbox \
      "Enter your HTTP Telegram Bot API Token:" 10 60 3>&1 1>&2 2>&3) || TELEGRAM_BOT_TOKEN=""
    
    TELEGRAM_CHAT_ID=$(whiptail --title "Telegram Destination Settings" --inputbox \
      "Enter target Telegram Chat ID / Channel ID:" 10 60 3>&1 1>&2 2>&3) || TELEGRAM_CHAT_ID=""
  fi

  # 6. Conditional Email Setup
  if [[ "$NOTIFY" == "email" || "$NOTIFY" == "both" ]]; then
    SMTP_HOST=$(whiptail --title "SMTP Server Settings" --inputbox \
      "Enter SMTP outbound host address:" 10 60 "smtp.gmail.com" 3>&1 1>&2 2>&3) || SMTP_HOST="smtp.gmail.com"
    
    SMTP_PORT=$(whiptail --title "SMTP Port Settings" --inputbox \
      "Enter SMTP infrastructure outbound port connection:" 10 60 "587" 3>&1 1>&2 2>&3) || SMTP_PORT="587"
    
    SMTP_USER=$(whiptail --title "SMTP Credentials Authentication" --inputbox \
      "Enter authentication system username/account email:" 10 60 "" 3>&1 1>&2 2>&3) || SMTP_USER=""
    
    # Hide password chars while typing
    SMTP_PASS=$(whiptail --title "SMTP Credentials Authentication" --passwordbox \
      "Enter your secure password string / app key:" 10 60 3>&1 1>&2 2>&3) || SMTP_PASS=""
    
    ALERT_FROM=$(whiptail --title "Email Source Routing" --inputbox \
      "Sender identity address (From header value):" 10 60 "$SMTP_USER" 3>&1 1>&2 2>&3) || ALERT_FROM=""
    
    ALERT_TO=$(whiptail --title "Email Target Destination" --inputbox \
      "Receiver identity address (To alert notification mailbox):" 10 60 "" 3>&1 1>&2 2>&3) || ALERT_TO=""
  fi

  # Write fully annotated config
  cat > "${CONFIG_DIR}/config" << CONF_EOF
# /etc/log-locate/config
# Global configuration for log-locate
# Per-file overrides go in /etc/log-locate/<filename>.conf

# ── Alerting ──────────────────────────────────────────────────────────────────
# Patterns that trigger a notification. Space-separated.
# Plain words = exact match:    ERROR WARN FATAL
# Prefix wildcard = key=value: user_id=* request_id=* host=*
ALERT_PATTERNS="${ALERT_PATTERNS}"  

# Notification channel: telegram | email | both
NOTIFY="${NOTIFY}"

# ── Telegram ──────────────────────────────────────────────────────────────────
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"

# ── Email (SMTP) ──────────────────────────────────────────────────────────────
SMTP_HOST="${SMTP_HOST}"
SMTP_PORT="${SMTP_PORT}"
SMTP_USER="${SMTP_USER}"
SMTP_PASS="${SMTP_PASS}"
ALERT_FROM="${ALERT_FROM}"
ALERT_TO="${ALERT_TO}"

# ── Batching & cooldown ───────────────────────────────────────────────────────
# Collect matching lines for this many seconds before sending one alert.
BATCH_SECONDS="${BATCH_SECONDS}"

# After sending an alert, suppress new alerts for this many seconds.
COOLDOWN_SECONDS="${COOLDOWN_SECONDS}"
CONF_EOF

  chmod 644 "${CONFIG_DIR}/config"
  chown root:root "${CONFIG_DIR}/config"
  
  whiptail --title "Setup Confirmed" --msgbox "Configuration dynamically exported and assigned cleanly to:\n${CONFIG_DIR}/config" 10 60

  # Offer immediate test using a clean yes/no prompt box
  if whiptail --title "Test Infrastructure Connectivity" --yesno "Would you like to send out a fast diagnostic alert pipeline test to your nodes right now?" 10 60; then
    "${BIN_DIR}/loglo" test-alert
  fi
fi

# ─── Registry file ────────────────────────────────────────────────────────────
# Must be readable and writable by all users so loglo status/list work without sudo
touch "${CONFIG_DIR}/registry"
chmod 666 "${CONFIG_DIR}/registry"

# ─── Journal access for the invoking user ─────────────────────────────────────
# Adds the real user (even under sudo) to systemd-journal so `loglo logs` works
REAL_USER="${SUDO_USER:-${USER:-}}"
if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
  if getent group systemd-journal &>/dev/null; then
    usermod -aG systemd-journal "$REAL_USER"
    echo "  Added $REAL_USER to systemd-journal group (re-login to apply)"
  fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}log-locate installed successfully!${RST}"
echo ""
echo "Next steps:"
echo ""
echo "  Re-login (or run 'newgrp systemd-journal') to apply journal group access."
echo ""
echo "  Start watching a log file:"
echo "    sudo loglo add /path/to/app.log --name myapp"
echo ""
echo "  View all watched files:"
echo "    loglo status"
echo ""
echo "  Tail daemon logs:"
echo "    loglo logs myapp"
echo ""
echo "  Send a test alert:"
echo "    loglo test-alert"
echo ""