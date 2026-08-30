#!/usr/bin/env bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/priv/scripts/codex-session-startup.sh"
PASS=0
FAIL=0
ERRORS=()
SERVER_PID=""
TEST_PORT=""
PORT_FILE=""

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

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf "  PASS: %s\n" "$desc"
    ((PASS++))
  else
    printf "  FAIL: %s\n    missing: %s\n" "$desc" "$needle"
    ERRORS+=("$desc")
    ((FAIL++))
  fi
}

assert_file_eventually_contains() {
  local desc="$1" needle="$2" file="$3"
  local haystack=""

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    haystack="$(cat "$file" 2>/dev/null || true)"
    if [[ "$haystack" == *"$needle"* ]]; then
      printf "  PASS: %s\n" "$desc"
      ((PASS++))
      return 0
    fi
    sleep 0.1
  done

  printf "  FAIL: %s\n    missing: %s\n" "$desc" "$needle"
  ERRORS+=("$desc")
  ((FAIL++))
}

setup_fake_eits() {
  TEST_HOME=$(mktemp -d /tmp/eits_codex_home_XXXXXX)
  FAKE_BIN=$(mktemp -d /tmp/eits_codex_bin_XXXXXX)
  CALL_LOG=$(mktemp /tmp/eits_codex_calls_XXXXXX.log)
  export TEST_HOME FAKE_BIN CALL_LOG

  cat > "$FAKE_BIN/eits" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
echo "$*" >> "$CALL_LOG"

case "$*" in
  "sessions get codex-test-session")
    echo '{"code":"not_found","error":"Session not found","status":404}'
    exit 1
    ;;
  "sessions get codex-existing-session")
    echo '{"id":124,"uuid":"codex-existing-session","agent_id":"existing-agent-uuid","agent_int_id":457,"project_id":1,"status":"idle","entrypoint":null}'
    exit 0
    ;;
  "sessions create --session-id codex-test-session --project web --project-path "*)
    echo '{"id":123,"uuid":"codex-test-session","agent_id":456,"agent_uuid":"agent-uuid","status":"working"}'
    exit 0
    ;;
  "projects list")
    printf '{"projects":[{"id":1,"name":"EITS Web","path":"%s"}]}\n' "$PWD"
    exit 0
    ;;
  "sessions update codex-test-session "*)
    echo '{"id":123,"uuid":"codex-test-session","status":"idle"}'
    exit 0
    ;;
  "sessions update codex-existing-session "*)
    echo '{"id":124,"uuid":"codex-existing-session","status":"idle","entrypoint":"cli"}'
    exit 0
    ;;
  *)
    echo '{"error":"unexpected command"}' >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$FAKE_BIN/eits"
}

start_tcp_probe_server() {
  PORT_FILE=$(mktemp /tmp/eits_codex_port_XXXXXX)
  python3 - "$PORT_FILE" <<'PY' >/dev/null 2>&1 &
import socket
import sys

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("127.0.0.1", 0))
sock.listen(8)

with open(sys.argv[1], "w", encoding="utf-8") as port_file:
    port_file.write(str(sock.getsockname()[1]))
    port_file.flush()

while True:
    conn, _addr = sock.accept()
    conn.close()
PY
  SERVER_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [ -s "$PORT_FILE" ]; then
      TEST_PORT=$(cat "$PORT_FILE")
      return 0
    fi
    sleep 0.1
  done
  return 1
}

cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "${TEST_HOME:-}" "${FAKE_BIN:-}"
  rm -f "${CALL_LOG:-}" "${PORT_FILE:-}"
}
trap cleanup EXIT

setup_fake_eits
start_tcp_probe_server

payload='{"session_id":"codex-test-session","model":"gpt-5.5","source":"startup"}'
output=$(printf '%s' "$payload" | HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" EITS_URL="http://127.0.0.1:$TEST_PORT/api/v1" bash "$SCRIPT" 2>/dev/null)
status=$?

assert_eq "exits cleanly" "0" "$status"
assert_contains "outputs session context" "EITS_SESSION_UUID" "$output"
assert_contains "outputs registered agent" "agent-uuid" "$output"

env_file="$TEST_HOME/.eits/codex/sessions/codex-test-session.env"
assert_eq "writes codex env file" "yes" "$([ -f "$env_file" ] && echo yes || echo no)"
assert_contains "env file includes session int id" "EITS_SESSION_ID=123" "$(cat "$env_file")"
assert_contains "env file includes agent uuid" "EITS_AGENT_UUID=agent-uuid" "$(cat "$env_file")"
assert_contains "env file includes agent int id" "EITS_AGENT_ID=456" "$(cat "$env_file")"
assert_contains "env file includes project id" "EITS_PROJECT_ID=1" "$(cat "$env_file")"
assert_contains "env file includes default codex entrypoint marker" "ENTRYPOINT=cli" "$(cat "$env_file")"
assert_contains "does not treat error JSON as found" "sessions create --session-id codex-test-session" "$(cat "$CALL_LOG")"
assert_contains "auto-created terminal session persists cli entrypoint" "--entrypoint cli" "$(cat "$CALL_LOG")"

existing_payload='{"session_id":"codex-existing-session","model":"gpt-5.5","source":"startup"}'
printf '%s' "$existing_payload" | HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" EITS_URL="http://127.0.0.1:$TEST_PORT/api/v1" bash "$SCRIPT" >/dev/null 2>&1
assert_file_eventually_contains "existing terminal session is patched with cli entrypoint" "sessions update codex-existing-session --status idle --project-id 1 --model gpt-5.5 --entrypoint cli" "$CALL_LOG"

rm -f "$env_file"
ENTRYPOINT="custom-entrypoint" printf '%s' "$payload" | HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" EITS_URL="http://127.0.0.1:$TEST_PORT/api/v1" ENTRYPOINT="custom-entrypoint" bash "$SCRIPT" >/dev/null 2>&1
assert_contains "env file preserves hook ENTRYPOINT when present" "ENTRYPOINT=custom-entrypoint" "$(cat "$env_file")"

printf 'export ENTRYPOINT=stale-saved-value\n' > "$env_file"
printf '%s' "$payload" | HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" EITS_URL="http://127.0.0.1:$TEST_PORT/api/v1" bash "$SCRIPT" >/dev/null 2>&1
assert_contains "env file ignores previously saved ENTRYPOINT when hook omits it" "ENTRYPOINT=cli" "$(cat "$env_file")"

if [ "$FAIL" -gt 0 ]; then
  printf "\nFAILED: %s\n" "${ERRORS[*]}"
  exit 1
fi

printf "\nAll codex startup hook tests passed (%d assertions).\n" "$PASS"
