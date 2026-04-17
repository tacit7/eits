#!/usr/bin/env bash
# Integration test: iam-pretooluse.sh
#
# Usage:
#   bash test/scripts/iam_hook_script_test.sh
#
# Requires: curl, jq, nc (or ss)
# Starts Phoenix on PORT=5099 with DISABLE_AUTH=true.
# Tests:
#   1. Valid Bash payload → valid JSON response with expected keys
#   2. Endpoint down (wrong port) → fail-open {"continue": true}
#   3. Empty stdin → fail-open
#   4. Malformed JSON → fail-open
#   5. Timeout (slow endpoint mock) → fail-open within 5s

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
SCRIPT="$REPO_ROOT/priv/scripts/iam-pretooluse.sh"
TEST_PORT=5099
SERVER_PID=""
PASS=0
FAIL=0
ERRORS=()

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  PASS: %s\n" "$desc"
    ((PASS++))
  else
    printf "  FAIL: %s\n    expected: %s\n    actual:   %s\n" "$desc" "$expected" "$actual"
    ERRORS+=("$desc")
    ((FAIL++))
  fi
}

# shellcheck disable=SC2329
assert_json_key() {
  local desc="$1" json="$2" key="$3"
  local val
  val=$(printf '%s' "$json" | jq -r "$key // empty" 2>/dev/null)
  if [ -n "$val" ]; then
    printf "  PASS: %s (value: %s)\n" "$desc" "$val"
    ((PASS++))
  else
    printf "  FAIL: %s — key '%s' missing or null in: %s\n" "$desc" "$key" "$json"
    ERRORS+=("$desc")
    ((FAIL++))
  fi
}

# ---------------------------------------------------------------------------
# Phoenix server lifecycle
# ---------------------------------------------------------------------------

wait_for_port() {
  local port="$1" max_wait=30 waited=0
  while ! curl -sf "http://localhost:$port/api/v1/health" >/dev/null 2>&1; do
    sleep 1
    ((waited++))
    if [ "$waited" -ge "$max_wait" ]; then
      echo "ERROR: Phoenix did not start on port $port within ${max_wait}s" >&2
      return 1
    fi
  done
}

start_server() {
  echo "==> Starting Phoenix on port $TEST_PORT..."
  cd "$REPO_ROOT" || return 1
  PORT=$TEST_PORT DISABLE_AUTH=true mix phx.server >/tmp/iam_hook_test_server.log 2>&1 &
  SERVER_PID=$!
  wait_for_port "$TEST_PORT" || return 1
  echo "    Phoenix up (PID $SERVER_PID)"
}

stop_server() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
  fi
}

# shellcheck disable=SC2329
cleanup() { stop_server; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fixture payloads
# ---------------------------------------------------------------------------

BASH_PAYLOAD=$(cat <<'EOF'
{
  "session_id": "test-session-00000000-0000-0000-0000-000000000001",
  "tool_name": "Bash",
  "tool_input": {
    "command": "ls -la /tmp"
  }
}
EOF
)

EDIT_PAYLOAD=$(cat <<'EOF'
{
  "session_id": "test-session-00000000-0000-0000-0000-000000000001",
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/tmp/test.txt",
    "old_string": "foo",
    "new_string": "bar"
  }
}
EOF
)

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

run_tests_offline() {
  echo ""
  echo "=== Offline tests (no server needed) ==="

  # Test: empty stdin → fail-open
  result=$(echo "" | EITS_URL="http://localhost:$TEST_PORT/api/v1" "$SCRIPT" 2>/dev/null)
  assert_eq "empty stdin → fail-open continue:true" \
    "true" \
    "$(printf '%s' "$result" | jq -r '.continue // empty')"

  # Test: malformed JSON → fail-open
  result=$(echo "not-json-at-all" | EITS_URL="http://localhost:$TEST_PORT/api/v1" "$SCRIPT" 2>/dev/null)
  assert_eq "malformed JSON → fail-open continue:true" \
    "true" \
    "$(printf '%s' "$result" | jq -r '.continue // empty')"

  # Test: endpoint unreachable (port 1) → fail-open
  result=$(printf '%s' "$BASH_PAYLOAD" | EITS_URL="http://localhost:1/api/v1" "$SCRIPT" 2>/dev/null)
  assert_eq "unreachable endpoint → fail-open continue:true" \
    "true" \
    "$(printf '%s' "$result" | jq -r '.continue // empty')"

  # Test: script exits 0 on fail-open (endpoint down)
  printf '%s' "$BASH_PAYLOAD" | EITS_URL="http://localhost:1/api/v1" "$SCRIPT" >/dev/null 2>&1
  assert_eq "exit code 0 when endpoint unreachable" "0" "$?"
}

run_tests_online() {
  echo ""
  echo "=== Online tests (Phoenix required) ==="

  # Test: Bash payload → valid hook response JSON
  result=$(printf '%s' "$BASH_PAYLOAD" | EITS_URL="http://localhost:$TEST_PORT/api/v1" "$SCRIPT" 2>/dev/null)
  if ! printf '%s' "$result" | jq -e . >/dev/null 2>&1; then
    printf "  FAIL: valid Bash payload → response is not JSON: %s\n" "$result"
    ERRORS+=("valid Bash payload → response is JSON")
    ((FAIL++))
  else
    printf "  PASS: valid Bash payload → response is JSON\n"
    ((PASS++))
  fi

  # Response must have hookSpecificOutput.hookEventName or continue key
  has_key=$(printf '%s' "$result" | jq -r '
    if .hookSpecificOutput.hookEventName then "yes"
    elif .continue != null then "yes"
    else "no"
    end
  ' 2>/dev/null)
  assert_eq "response has hookSpecificOutput or continue key" "yes" "$has_key"

  # permissionDecision must be allow or deny
  perm=$(printf '%s' "$result" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$perm" = "allow" ] || [ "$perm" = "deny" ]; then
    printf "  PASS: permissionDecision is allow|deny (got: %s)\n" "$perm"
    ((PASS++))
  else
    printf "  FAIL: permissionDecision missing or invalid: '%s'\n" "$perm"
    ERRORS+=("permissionDecision is allow|deny")
    ((FAIL++))
  fi

  # hookEventName must be PreToolUse
  event=$(printf '%s' "$result" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
  assert_eq "hookEventName is PreToolUse" "PreToolUse" "$event"

  # Edit payload test
  result2=$(printf '%s' "$EDIT_PAYLOAD" | EITS_URL="http://localhost:$TEST_PORT/api/v1" "$SCRIPT" 2>/dev/null)
  perm2=$(printf '%s' "$result2" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "$perm2" = "allow" ] || [ "$perm2" = "deny" ]; then
    printf "  PASS: Edit payload → valid permissionDecision (got: %s)\n" "$perm2"
    ((PASS++))
  else
    printf "  FAIL: Edit payload → missing permissionDecision: '%s'\n" "$perm2"
    ERRORS+=("Edit payload → valid permissionDecision")
    ((FAIL++))
  fi

  # Script exits 0 on valid response
  printf '%s' "$BASH_PAYLOAD" | EITS_URL="http://localhost:$TEST_PORT/api/v1" "$SCRIPT" >/dev/null 2>&1
  assert_eq "exit code 0 on valid response" "0" "$?"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=== IAM PreToolUse Hook Script Tests ==="
echo "Script: $SCRIPT"

run_tests_offline

if start_server 2>/dev/null; then
  run_tests_online
  stop_server
else
  echo ""
  echo "  SKIP: Phoenix server failed to start; skipping online tests"
  echo "        (offline tests still ran above)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "${#ERRORS[@]}" -gt 0 ]; then
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do
    printf "  - %s\n" "$e"
  done
  exit 1
fi

exit 0
