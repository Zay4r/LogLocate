#!/usr/bin/env bash
# install.sh — log-locate installer
#
# Installs:
#   /usr/local/bin/log-locate-daemon  — the file watcher/alerter daemon
#   /usr/local/bin/loglo              — CLI wrapper (add / remove / status / logs)
#   /etc/systemd/system/log-locate@.service  — systemd template
#   /etc/log-locate/config            — default config (not overwritten if exists)
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

# ─── Install daemon binary ────────────────────────────────────────────────────
echo "  Installing daemon..."
_get_file "log-locate-daemon" "${BIN_DIR}/log-locate-daemon"
chmod +x "${BIN_DIR}/log-locate-daemon"
echo "  Installed: ${BIN_DIR}/log-locate-daemon"

# ─── Install loglo CLI wrapper ────────────────────────────────────────────────
echo "  Installing loglo CLI..."
cat > "${BIN_DIR}/loglo" << 'LOGLO_EOF'
#!/usr/bin/env bash
# loglo — log-locate CLI wrapper

set -euo pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
RST='\033[0m'

_usage() {
  echo "Usage:"
  echo "  loglo add <logfile>       Start watching a log file"
  echo "  loglo remove <logfile>    Stop watching a log file"
  echo "  loglo status              List all watched files"
  echo "  loglo logs <logfile>      Tail live daemon logs for a file"
  exit 1
}

_path_to_instance() {
  local path
  path="$(realpath "$1")"
  echo "${path#/}" | tr '/' '-'
}

_require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run as root: sudo loglo $*${RST}" >&2
    exit 1
  fi
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
    if systemctl is-active --quiet "$UNIT" 2>/dev/null; then
      echo -e "${YLW}Already watching: $FILE${RST}"
      exit 0
    fi
    echo -e "${BLU}Watching: $FILE${RST}"
    systemctl enable --now "$UNIT"
    echo -e "${GRN}Started: $UNIT${RST}"
    ;;

  remove)
    [[ -z "${2:-}" ]] && { echo -e "${RED}Usage: loglo remove <logfile>${RST}" >&2; exit 1; }
    _require_root remove "$@"
    FILE="$(realpath "$2")"
    INSTANCE="$(_path_to_instance "$FILE")"
    UNIT="log-locate@${INSTANCE}.service"
    if ! systemctl list-units --all | grep -q "$UNIT"; then
      echo -e "${YLW}Not watching: $FILE${RST}"
      exit 0
    fi
    systemctl disable --now "$UNIT" 2>/dev/null || true
    echo -e "${GRN}Stopped: $UNIT${RST}"
    ;;

  status)
    echo -e "${BLU}Watched log files:${RST}"
    FOUND=0
    while IFS= read -r unit; do
      [[ -z "$unit" ]] && continue
      instance="${unit#log-locate@}"
      instance="${instance%.service}"
      filepath="/$(echo "$instance" | tr '-' '/')"
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
echo "     sudo nano /etc/log-locate/config"
echo ""
echo "  2. Start watching a log file:"
echo "     sudo loglo add /home/ubuntu/server.log"
echo ""
echo "  3. View all watched files:"
echo "     loglo status"
echo ""
echo "  4. Tail daemon logs:"
echo "     loglo logs /home/ubuntu/server.log"
echo ""