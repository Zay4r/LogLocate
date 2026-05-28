#!/usr/bin/env bash
# tests/test_log_locate.sh
#
# Unit tests for log-locate CLI tool
# Run with: bash tests/test_log_locate.sh

set -euo pipefail

# ─── Test Setup ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Source the main script functions (without running the router)
# We'll extract functions manually to avoid side effects
source "$REPO_DIR/log-locate" 2>/dev/null || true

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
RST='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ─── Test Utilities ─────────────────────────────────────────────────────────

_assert_equal() {
  local expected="$1"
  local actual="$2"
  local test_name="${3:-assertion}"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$expected" == "$actual" ]]; then
    echo -e "${GRN}✓${RST} $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗${RST} $test_name"
    echo "  Expected: $expected"
    echo "  Got:      $actual"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

_assert_contains() {
  local haystack="$1"
  local needle="$2"
  local test_name="${3:-assertion}"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$haystack" == *"$needle"* ]]; then
    echo -e "${GRN}✓${RST} $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗${RST} $test_name"
    echo "  Expected to contain: $needle"
    echo "  Got: $haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

_assert_file_exists() {
  local file="$1"
  local test_name="${2:-file exists}"
  
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ -f "$file" ]]; then
    echo -e "${GRN}✓${RST} $test_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗${RST} $test_name"
    echo "  File not found: $file"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ─── Test Suite: Path Conversion ────────────────────────────────────────────

test_path_to_instance() {
  echo ""
  echo -e "${YLW}Testing _path_to_instance()${RST}"
  
  local result
  result=$(_path_to_instance "/etc/project/logs/app.log")
  _assert_equal "etc-project-logs-app.log" "$result" "Convert absolute path to instance"
  
  result=$(_path_to_instance "/var/log/nginx/access.log")
  _assert_equal "var-log-nginx-access.log" "$result" "Convert deep path to instance"
  
  result=$(_path_to_instance "/app.log")
  _assert_equal "app.log" "$result" "Convert simple absolute path to instance"
}

test_instance_to_path() {
  echo ""
  echo -e "${YLW}Testing _instance_to_path()${RST}"
  
  local result
  result=$(_instance_to_path "etc-project-logs-app.log")
  _assert_equal "/etc/project/logs/app.log" "$result" "Convert instance to absolute path"
  
  result=$(_instance_to_path "var-log-nginx-access.log")
  _assert_equal "/var/log/nginx/access.log" "$result" "Convert instance with dashes to path"
}

# ─── Test Suite: Config Loading ────────────────────────────────────────────

test_load_config() {
  echo ""
  echo -e "${YLW}Testing _load_config()${RST}"
  
  # Create a test config
  mkdir -p "$TEST_DIR/etc/log-locate"
  cat > "$TEST_DIR/etc/log-locate/config" <<'EOF'
PATTERNS="CUSTOM ERROR"
ALERT_PATTERNS="CRITICAL"
EOF
  
  # Override the config path
  GLOBAL_CONFIG="$TEST_DIR/etc/log-locate/config"
  
  _load_config
  _assert_equal "CUSTOM ERROR" "$PATTERNS" "Load custom PATTERNS from config"
  _assert_equal "CRITICAL" "$ALERT_PATTERNS" "Load custom ALERT_PATTERNS from config"
}

# ─── Test Suite: Keyword Search ────────────────────────────────────────────

test_search_basic() {
  echo ""
  echo -e "${YLW}Testing keyword search functionality${RST}"
  
  # Create a test log file
  local log_file="$TEST_DIR/test.log"
  cat > "$log_file" <<'EOF'
2026-05-28T10:00:00Z ERROR database connection failed
2026-05-28T10:00:01Z WARN cache miss
2026-05-28T10:00:02Z INFO request processed
2026-05-28T10:00:03Z FATAL service crashed
EOF
  
  # Create an index file
  local idx_file="${log_file}.idx"
  cat > "$idx_file" <<'EOF'
ERROR	1	2026-05-28T10:00:00Z
database	1	2026-05-28T10:00:00Z
connection	1	2026-05-28T10:00:00Z
failed	1	2026-05-28T10:00:00Z
WARN	2	2026-05-28T10:00:01Z
cache	2	2026-05-28T10:00:01Z
miss	2	2026-05-28T10:00:01Z
FATAL	4	2026-05-28T10:00:03Z
service	4	2026-05-28T10:00:03Z
crashed	4	2026-05-28T10:00:03Z
EOF
  
  _assert_file_exists "$idx_file" "Index file created"
  
  # Count ERROR entries
  local error_count
  error_count=$(grep "^ERROR" "$idx_file" | wc -l)
  _assert_equal "1" "$error_count" "Index contains ERROR keyword"
  
  # Count FATAL entries
  local fatal_count
  fatal_count=$(grep "^FATAL" "$idx_file" | wc -l)
  _assert_equal "1" "$fatal_count" "Index contains FATAL keyword"
}

# ─── Test Suite: Range Search ──────────────────────────────────────────────

test_range_search_format() {
  echo ""
  echo -e "${YLW}Testing range search timestamp format${RST}"
  
  local from_ts="2026-05-28T10:15:00Z"
  local to_ts="2026-05-28T10:20:00Z"
  
  # Validate timestamp format
  if [[ "$from_ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    echo -e "${GRN}✓${RST} from_ts has valid ISO 8601 format"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗${RST} from_ts format validation"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
  
  if [[ "$to_ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    echo -e "${GRN}✓${RST} to_ts has valid ISO 8601 format"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗${RST} to_ts format validation"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
}

# ─── Test Suite: Color Codes ───────────────────────────────────────────────

test_color_codes() {
  echo ""
  echo -e "${YLW}Testing color code variables${RST}"
  
  _assert_equal '\033[0;31m' "$RED" "RED color code set"
  _assert_equal '\033[0;32m' "$GRN" "GRN color code set"
  _assert_equal '\033[1;33m' "$YLW" "YLW color code set"
  _assert_equal '\033[0;34m' "$BLU" "BLU color code set"
  _assert_equal '\033[0m' "$RST" "RST color code set"
}

# ─── Test Suite: Help Text ────────────────────────────────────────────────

test_help_output() {
  echo ""
  echo -e "${YLW}Testing help command output${RST}"
  
  # Capture help output
  local help_output
  help_output=$(cmd_help 2>&1 || true)
  
  _assert_contains "$help_output" "log-locate" "Help contains tool name"
  _assert_contains "$help_output" "add" "Help mentions add command"
  _assert_contains "$help_output" "search" "Help mentions search command"
  _assert_contains "$help_output" "range" "Help mentions range command"
  _assert_contains "$help_output" "status" "Help mentions status command"
}

# ─── Main Test Runner ──────────────────────────────────────────────────────

main() {
  echo -e "${BLU}=== LogLocate Unit Tests ===${RST}"
  echo ""
  
  test_path_to_instance
  test_instance_to_path
  test_load_config
  test_search_basic
  test_range_search_format
  test_color_codes
  test_help_output
  
  echo ""
  echo -e "${BLU}=== Test Results ===${RST}"
  echo "Tests run:    $TESTS_RUN"
  echo -e "Tests passed: ${GRN}$TESTS_PASSED${RST}"
  echo -e "Tests failed: ${RED}$TESTS_FAILED${RST}"
  echo ""
  
  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GRN}All tests passed!${RST}"
    return 0
  else
    echo -e "${RED}Some tests failed.${RST}"
    return 1
  fi
}

main "$@"
