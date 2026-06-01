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
exec </dev/tty

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
cat > "${BIN_DIR}/loglo" << 'LOGLO_EOF'
#!/usr/bin/env bash
# loglo — log-locate CLI

set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
RST='\033[0m'

CONFIG_FILE="/etc/log-locate/config"

_usage() {
  echo "Usage:"
  echo "  loglo add <logfile>         Start watching a log file"
  echo "  loglo remove <logfile>      Stop watching a log file"
  echo "  loglo remove --all          Stop watching all files"
  echo "  loglo status                List all watched files"
  echo "  loglo logs <logfile>        Tail live daemon logs for a file"
  echo "  loglo test-alert            Send a test notification using current config"
  exit 1
}

_path_to_instance() {
  local path
  path="$(realpath "$1")"
  systemd-escape --path "$path"
}

_instance_to_path() {
  systemd-escape --unescape --path "$1"
}

_require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run as root: sudo loglo $*${RST}" >&2
    exit 1
  fi
}

_load_config() {
  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
}

CMD="${1:-}"
[[ -z "$CMD" ]] && _usage

case "$CMD" in

  add)
    [[ -z "${2:-}" ]] && { echo -e "${RED}Usage: loglo add <logfile>${RST}" >&2; exit 1; }
    _require_root add "$@"
    FILE="$(realpath "$2")"
    INSTANCE="$(_path_to_instance "$FILE")"
    UNIT="log-locate@${INSTANCE}.service"

    if [[ ! -f "$FILE" ]]; then
      echo -e "${YLW}Warning: $FILE does not exist yet. The daemon will start watching once it is created.${RST}"
    fi

    FILE_DIR="$(dirname "$FILE")"
    if ! sudo -u log-locate test -r "$FILE_DIR" 2>/dev/null; then
      setfacl -m u:log-locate:rx "$FILE_DIR" 2>/dev/null || \
        chmod o+rx "$FILE_DIR" 2>/dev/null || \
        echo -e "${YLW}  Could not set permissions on $FILE_DIR — you may need to do this manually.${RST}"
    fi
    if [[ -f "$FILE" ]] && ! sudo -u log-locate test -r "$FILE" 2>/dev/null; then
      setfacl -m u:log-locate:r "$FILE" 2>/dev/null || \
        chmod o+r "$FILE" 2>/dev/null || \
        echo -e "${YLW}  Could not set read permission on $FILE — you may need to do this manually.${RST}"
    fi

    if systemctl is-active --quiet "$UNIT" 2>/dev/null; then
      echo -e "${YLW}Already watching: $FILE${RST}"
      exit 0
    fi

    systemctl enable --now "$UNIT"
    echo -e "${GRN}Now watching: $FILE${RST}"
    ;;

  remove)
    [[ -z "${2:-}" ]] && { echo -e "${RED}Usage: loglo remove <logfile> | --all${RST}" >&2; exit 1; }
    _require_root remove "$@"

    if [[ "$2" == "--all" ]]; then
      FOUND=0
      while IFS= read -r unit; do
        [[ -z "$unit" ]] && continue
        systemctl disable --now "$unit" 2>/dev/null || true
        echo -e "${GRN}Stopped: $unit${RST}"
        FOUND=1
      done < <(systemctl list-units --type=service --all --no-legend \
        | awk '{print $1}' \
        | grep '^log-locate@')
      [[ $FOUND -eq 0 ]] && echo "  (no active watchers)"
    else
      FILE="$(realpath "$2")"
      INSTANCE="$(_path_to_instance "$FILE")"
      UNIT="log-locate@${INSTANCE}.service"
      if ! systemctl list-units --all | grep -q "$UNIT"; then
        echo -e "${YLW}Not watching: $FILE${RST}"
        exit 0
      fi
      systemctl disable --now "$UNIT" 2>/dev/null || true
      echo -e "${GRN}Stopped watching: $FILE${RST}"
    fi
    ;;

  status)
    echo -e "${BLU}Watched log files:${RST}"
    FOUND=0
    while IFS= read -r unit; do
      [[ -z "$unit" ]] && continue
      instance="${unit#log-locate@}"
      instance="${instance%.service}"
      filepath="$(_instance_to_path "$instance")"
      state=$(systemctl is-active "$unit" 2>/dev/null || echo "unknown")
      case "$state" in
        active)  color="$GRN" ;;
        failed)  color="$RED" ;;
        *)       color="$YLW" ;;
      esac
      echo -e "  ${color}[$state]${RST} $filepath"
      FOUND=1
    done < <(systemctl list-units --type=service --all --no-legend \
      | awk '{print $1}' \
      | grep '^log-locate@')
    [[ $FOUND -eq 0 ]] && echo "  (none)"
    ;;

  logs)
    [[ -z "${2:-}" ]] && { echo -e "${RED}Usage: loglo logs <logfile>${RST}" >&2; exit 1; }
    FILE="$(realpath "$2")"
    INSTANCE="$(_path_to_instance "$FILE")"
    UNIT="log-locate@${INSTANCE}.service"
    exec journalctl -u "$UNIT" -f
    ;;

  test-alert)
    _load_config
    HOSTNAME="$(hostname)"
    TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    MSG="🔔 [log-locate] Test alert from ${HOSTNAME} at ${TIMESTAMP}. If you received this, notifications are working correctly."

    NOTIFY="${NOTIFY:-telegram}"
    SENT=0

    if [[ "$NOTIFY" == "telegram" || "$NOTIFY" == "both" ]]; then
      if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        echo -e "${RED}Telegram not configured (TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID missing in config)${RST}" >&2
      else
        RESP=$(curl -sf -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
          -d chat_id="${TELEGRAM_CHAT_ID}" \
          -d text="${MSG}" || echo "FAILED")
        if echo "$RESP" | grep -q '"ok":true'; then
          echo -e "${GRN}Telegram: test message sent successfully.${RST}"
          SENT=1
        else
          echo -e "${RED}Telegram: failed to send. Response: $RESP${RST}" >&2
        fi
      fi
    fi

    if [[ "$NOTIFY" == "email" || "$NOTIFY" == "both" ]]; then
      if [[ -z "${SMTP_USER:-}" || -z "${SMTP_PASS:-}" || -z "${ALERT_TO:-}" ]]; then
        echo -e "${RED}Email not configured (SMTP_USER / SMTP_PASS / ALERT_TO missing in config)${RST}" >&2
      else
        curl -sf \
          --url "smtp://${SMTP_HOST}:${SMTP_PORT}" \
          --ssl-reqd \
          --mail-from "${ALERT_FROM}" \
          --mail-rcpt "${ALERT_TO}" \
          --user "${SMTP_USER}:${SMTP_PASS}" \
          -T <(echo -e "From: ${ALERT_FROM}\nTo: ${ALERT_TO}\nSubject: [log-locate] Test Alert\n\n${MSG}") \
          && echo -e "${GRN}Email: test message sent successfully.${RST}" && SENT=1 \
          || echo -e "${RED}Email: failed to send.${RST}" >&2
      fi
    fi

    [[ $SENT -eq 0 ]] && echo -e "${YLW}No notifications sent. Check your config: ${CONFIG_FILE}${RST}"
    ;;

  *)
    echo -e "${RED}Unknown command: $CMD${RST}" >&2
    _usage
    ;;
esac
LOGLO_EOF

chmod +x "${BIN_DIR}/loglo"
echo "  Installed: ${BIN_DIR}/loglo"

# ─── Install systemd service template ────────────────────────────────────────
echo "  Installing systemd service template..."
_get_file "log-locate_.service" "${SERVICE_DIR}/log-locate@.service"
systemctl daemon-reload
echo "  Installed: ${SERVICE_DIR}/log-locate@.service"

# ─── Interactive config wizard ────────────────────────────────────────────────
mkdir -p "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"
chown root:log-locate "$CONFIG_DIR"

_ask() {
  # _ask VARNAME "Prompt text" "default"
  local var="$1" prompt="$2" default="$3"
  local input
  echo -ne "  ${prompt}${DIM}${default:+ [$default]}${RST}: "
  read -r input
  # Use default if user pressed enter with no input
  printf -v "$var" '%s' "${input:-$default}"
}

_ask_secret() {
  local var="$1" prompt="$2"
  local input
  echo -ne "  ${prompt}: "
  read -rs input
  echo ""
  printf -v "$var" '%s' "$input"
}

CONFIG_EXISTS=false
[[ -f "${CONFIG_DIR}/config" ]] && CONFIG_EXISTS=true

if $CONFIG_EXISTS; then
  echo ""
  echo -e "${YLW}Config already exists at ${CONFIG_DIR}/config${RST}"
  echo -ne "  Re-run the setup wizard? [y/N]: "
  read -r REDO </dev/tty
  [[ "${REDO,,}" != "y" ]] && {
    echo "  Skipping — keeping existing config."
    CONFIG_DONE=true
  }
fi

if [[ "${CONFIG_DONE:-false}" != "true" ]]; then
  echo ""
  echo -e "${BLU}─── Configuration wizard ────────────────────────────────────────${RST}"
  echo ""

  # Notification channel
  echo -e "  Notification channel:"
  echo -e "    ${DIM}1) telegram${RST}"
  echo -e "    ${DIM}2) email${RST}"
  echo -e "    ${DIM}3) both${RST}"
  echo -ne "  Choose [1/2/3] ${DIM}[1]${RST}: "
  read -r NOTIFY_CHOICE
  case "${NOTIFY_CHOICE:-1}" in
    2) NOTIFY="email" ;;
    3) NOTIFY="both" ;;
    *) NOTIFY="telegram" ;;
  esac

  # Alert patterns
  _ask ALERT_PATTERNS "Alert patterns (space-separated)" "ERROR FATAL WARN"

  # Batching / cooldown
  _ask BATCH_SECONDS   "Batch window in seconds" "10"
  _ask COOLDOWN_SECONDS "Cooldown after alert in seconds" "300"

  # Telegram
  TELEGRAM_BOT_TOKEN=""
  TELEGRAM_CHAT_ID=""
  if [[ "$NOTIFY" == "telegram" || "$NOTIFY" == "both" ]]; then
    echo ""
    echo -e "  ${BLU}Telegram settings${RST}"
    _ask_secret TELEGRAM_BOT_TOKEN "Bot token"
    _ask        TELEGRAM_CHAT_ID   "Chat ID" ""
  fi

  # Email
  SMTP_HOST="smtp.gmail.com"
  SMTP_PORT="587"
  SMTP_USER=""
  SMTP_PASS=""
  ALERT_FROM=""
  ALERT_TO=""
  if [[ "$NOTIFY" == "email" || "$NOTIFY" == "both" ]]; then
    echo ""
    echo -e "  ${BLU}Email (SMTP) settings${RST}"
    _ask        SMTP_HOST  "SMTP host"       "smtp.gmail.com"
    _ask        SMTP_PORT  "SMTP port"       "587"
    _ask        SMTP_USER  "SMTP username"   ""
    _ask_secret SMTP_PASS  "SMTP password"
    _ask        ALERT_FROM "From address"    ""
    _ask        ALERT_TO   "To address"      ""
  fi

  # Write config
  cat > "${CONFIG_DIR}/config" << CONF_EOF
# /etc/log-locate/config
# Generated by installer on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Per-file overrides go in /etc/log-locate/<filename>.conf

# ── Alerting ──────────────────────────────────────────────────────────────────
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
BATCH_SECONDS="${BATCH_SECONDS}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS}"
CONF_EOF

  chmod 640 "${CONFIG_DIR}/config"
  chown root:log-locate "${CONFIG_DIR}/config"
  echo ""
  echo -e "${GRN}  Config written to ${CONFIG_DIR}/config${RST}"

  # Offer immediate test
  echo ""
  echo -ne "  Send a test alert now? [Y/n]: "
  read -r DO_TEST
  if [[ "${DO_TEST,,}" != "n" ]]; then
    "${BIN_DIR}/loglo" test-alert
  fi
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GRN}log-locate installed successfully!${RST}"
echo ""
echo "Next steps:"
echo ""
echo "  Start watching a log file:"
echo "    sudo loglo add /home/ubuntu/server.log"
echo ""
echo "  View all watched files:"
echo "    loglo status"
echo ""
echo "  Tail daemon logs:"
echo "    loglo logs /home/ubuntu/server.log"
echo ""