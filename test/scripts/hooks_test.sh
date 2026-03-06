#!/usr/bin/env bash
# Hook script unit tests
# Tests eits-pre-tool-use.sh, eits-session-stop.sh, eits-prompt-submit.sh,
# eits-pre-compact.sh, and sql helper scripts.
#
# Usage: bash test/scripts/hooks_test.sh
# Requires: jq, sqlite3

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)"
PASS=0
FAIL=0
ERRORS=()

# --- Test harness -------------------------------------------------------------

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc"
    echo "        expected: '$expected'"
    echo "        actual:   '$actual'"
    ERRORS+=("$desc")
    ((FAIL++))
  fi
}

assert_exit() {
  local desc="$1" expected_code="$2" actual_code="$3"
  if [ "$expected_code" = "$actual_code" ]; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc"
    echo "        expected exit: $expected_code"
    echo "        actual exit:   $actual_code"
    ERRORS+=("$desc")
    ((FAIL++))
  fi
}

# --- SQLite test DB -----------------------------------------------------------

# Sets global TEST_DB and exports EITS_DB_PATH
init_db() {
  TEST_DB=$(mktemp /tmp/eits_test_XXXXXX.db)
  export EITS_DB_PATH="$TEST_DB"

  sqlite3 "$TEST_DB" "
    CREATE TABLE sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT UNIQUE,
      name TEXT,
      status TEXT DEFAULT 'idle',
      last_activity_at TEXT,
      agent_id INTEGER
    );
    CREATE TABLE agents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT UNIQUE,
      parent_agent_id INTEGER
    );
    CREATE TABLE tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER,
      state_id INTEGER,
      archived INTEGER DEFAULT 0
    );
    CREATE TABLE task_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id INTEGER,
      session_id INTEGER
    );
    CREATE TABLE workflow_states (
      id INTEGER PRIMARY KEY,
      name TEXT
    );
    INSERT INTO workflow_states VALUES (2, 'In Progress');
  "
}

cleanup_db() {
  [ -f "${TEST_DB:-}" ] && rm -f "$TEST_DB"
  unset EITS_DB_PATH TEST_DB
}

db_query() {
  sqlite3 "$TEST_DB" "$1"
}

# Puts a fake nats binary on PATH that logs calls to NATS_LOG
setup_nats_mock() {
  NATS_LOG=$(mktemp /tmp/nats_calls_XXXXXX.log)
  NATS_BIN_DIR=$(mktemp -d /tmp/nats_bin_XXXXXX)
  export NATS_LOG
  cat > "$NATS_BIN_DIR/nats" << 'NATS_MOCK'
#!/usr/bin/env bash
echo "nats $*" >> "$NATS_LOG"
NATS_MOCK
  chmod +x "$NATS_BIN_DIR/nats"
  export PATH="$NATS_BIN_DIR:$PATH"
}

cleanup_nats_mock() {
  rm -f "${NATS_LOG:-}"
  rm -rf "${NATS_BIN_DIR:-}"
  unset NATS_LOG NATS_BIN_DIR
}

# ---------------------------------------------------------------------------
# sql/update-session-status.sh
# ---------------------------------------------------------------------------
echo ""
echo "=== sql/update-session-status.sh ==="

init_db
SESSION_UUID="update-status-uuid"
db_query "INSERT INTO sessions (uuid, status) VALUES ('$SESSION_UUID', 'working');"

"$SCRIPTS_DIR/sql/update-session-status.sh" "$SESSION_UUID" "idle"
STATUS=$(db_query "SELECT status FROM sessions WHERE uuid = '$SESSION_UUID';")
assert_eq "sets status to idle" "idle" "$STATUS"

"$SCRIPTS_DIR/sql/update-session-status.sh" "$SESSION_UUID" "working"
STATUS=$(db_query "SELECT status FROM sessions WHERE uuid = '$SESSION_UUID';")
assert_eq "sets status to working" "working" "$STATUS"

"$SCRIPTS_DIR/sql/update-session-status.sh" "$SESSION_UUID" "compacting"
STATUS=$(db_query "SELECT status FROM sessions WHERE uuid = '$SESSION_UUID';")
assert_eq "sets status to compacting" "compacting" "$STATUS"

"$SCRIPTS_DIR/sql/update-session-status.sh" "" "idle" 2>/dev/null; CODE=$?
assert_exit "exits 1 for empty session_id" "1" "$CODE"

cleanup_db

# ---------------------------------------------------------------------------
# sql/update-session-to-working.sh
# ---------------------------------------------------------------------------
echo ""
echo "=== sql/update-session-to-working.sh ==="

init_db
SESSION_UUID="to-working-uuid"
db_query "INSERT INTO sessions (uuid, status) VALUES ('$SESSION_UUID', 'idle');"

"$SCRIPTS_DIR/sql/update-session-to-working.sh" "$SESSION_UUID"
STATUS=$(db_query "SELECT status FROM sessions WHERE uuid = '$SESSION_UUID';")
assert_eq "sets idle session to working" "working" "$STATUS"

"$SCRIPTS_DIR/sql/update-session-to-working.sh" "$SESSION_UUID"
STATUS=$(db_query "SELECT status FROM sessions WHERE uuid = '$SESSION_UUID';")
assert_eq "skips update when already working" "working" "$STATUS"

cleanup_db

# ---------------------------------------------------------------------------
# sql/check-active-todo.sh
# ---------------------------------------------------------------------------
echo ""
echo "=== sql/check-active-todo.sh ==="

init_db
SESSION_UUID="check-todo-uuid"
db_query "INSERT INTO sessions (id, uuid, status) VALUES (1, '$SESSION_UUID', 'working');"

"$SCRIPTS_DIR/sql/check-active-todo.sh" "$SESSION_UUID" 2>/dev/null; CODE=$?
assert_exit "exits non-zero when no active todo" "1" "$CODE"

# Add task + task_sessions join
db_query "INSERT INTO tasks (id, session_id, state_id, archived) VALUES (1, 1, 2, 0);"
db_query "INSERT INTO task_sessions (task_id, session_id) VALUES (1, 1);"
"$SCRIPTS_DIR/sql/check-active-todo.sh" "$SESSION_UUID" 2>/dev/null; CODE=$?
assert_exit "exits 0 when active todo exists" "0" "$CODE"

# Archived task should not count
db_query "UPDATE tasks SET archived = 1 WHERE id = 1;"
"$SCRIPTS_DIR/sql/check-active-todo.sh" "$SESSION_UUID" 2>/dev/null; CODE=$?
assert_exit "exits non-zero when only archived todos" "1" "$CODE"

cleanup_db

# ---------------------------------------------------------------------------
# eits-session-stop.sh
# ---------------------------------------------------------------------------
echo ""
echo "=== eits-session-stop.sh ==="

init_db
setup_nats_mock
SESSION_UUID="stop-uuid"
db_query "INSERT INTO sessions (uuid, status) VALUES ('$SESSION_UUID', 'working');"

echo "{\"session_id\": \"$SESSION_UUID\", \"stop_hook_active\": false}" \
  | "$SCRIPTS_DIR/eits-session-stop.sh" 2>/dev/null
STATUS=$(db_query "SELECT status FROM sessions WHERE uuid = '$SESSION_UUID';")
assert_eq "stop sets status to idle" "idle" "$STATUS"

# stop_hook_active guard — should skip update
db_query "UPDATE sessions SET status = 'working' WHERE uuid = '$SESSION_UUID';"
echo "{\"session_id\": \"$SESSION_UUID\", \"stop_hook_active\": true}" \
  | "$SCRIPTS_DIR/eits-session-stop.sh" 2>/dev/null
STATUS=$(db_query "SELECT status FROM sessions WHERE uuid = '$SESSION_UUID';")
assert_eq "stop_hook_active guard skips update" "working" "$STATUS"

echo "" | "$SCRIPTS_DIR/eits-session-stop.sh" 2>/dev/null; CODE=$?
assert_exit "exits 0 on empty input" "0" "$CODE"

cleanup_nats_mock
cleanup_db

# ---------------------------------------------------------------------------
# eits-prompt-submit.sh
# ---------------------------------------------------------------------------
echo ""
echo "=== eits-prompt-submit.sh ==="

init_db
setup_nats_mock
SESSION_UUID="prompt-uuid"
db_query "INSERT INTO sessions (uuid, status) VALUES ('$SESSION_UUID', 'idle');"

echo "{\"session_id\": \"$SESSION_UUID\"}" \
  | "$SCRIPTS_DIR/eits-prompt-submit.sh" 2>/dev/null
STATUS=$(db_query "SELECT status FROM sessions WHERE uuid = '$SESSION_UUID';")
assert_eq "prompt submit sets status to working" "working" "$STATUS"

# Already working — stays working
echo "{\"session_id\": \"$SESSION_UUID\"}" \
  | "$SCRIPTS_DIR/eits-prompt-submit.sh" 2>/dev/null
STATUS=$(db_query "SELECT status FROM sessions WHERE uuid = '$SESSION_UUID';")
assert_eq "prompt submit stays working when already working" "working" "$STATUS"

cleanup_nats_mock
cleanup_db

# ---------------------------------------------------------------------------
# eits-pre-compact.sh
# ---------------------------------------------------------------------------
echo ""
echo "=== eits-pre-compact.sh ==="

init_db
setup_nats_mock
SESSION_UUID="compact-uuid"
db_query "INSERT INTO sessions (uuid, status) VALUES ('$SESSION_UUID', 'working');"

echo "{\"session_id\": \"$SESSION_UUID\"}" \
  | "$SCRIPTS_DIR/eits-pre-compact.sh" 2>/dev/null
STATUS=$(db_query "SELECT status FROM sessions WHERE uuid = '$SESSION_UUID';")
assert_eq "pre-compact sets status to compacting" "compacting" "$STATUS"

echo "" | "$SCRIPTS_DIR/eits-pre-compact.sh" 2>/dev/null; CODE=$?
assert_exit "exits 0 on empty input" "0" "$CODE"

cleanup_nats_mock
cleanup_db

# ---------------------------------------------------------------------------
# eits-pre-tool-use.sh — blocking logic
# ---------------------------------------------------------------------------
echo ""
echo "=== eits-pre-tool-use.sh ==="

init_db
setup_nats_mock
SESSION_UUID="pretool-uuid"
AGENT_UUID="agent-pretool-uuid"
db_query "INSERT INTO agents (id, uuid, parent_agent_id) VALUES (1, '$AGENT_UUID', NULL);"
db_query "INSERT INTO sessions (id, uuid, status, agent_id) VALUES (1, '$SESSION_UUID', 'working', 1);"

# No session name + Edit tool → denial JSON
OUTPUT=$(echo "{\"session_id\": \"$SESSION_UUID\", \"tool_name\": \"Edit\", \"tool_input\": {}}" \
  | "$SCRIPTS_DIR/eits-pre-tool-use.sh" 2>/dev/null)
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
assert_eq "blocks Edit when session has no name" "deny" "$DECISION"

# Named session, no active todo → denial JSON
db_query "UPDATE sessions SET name = 'My Session' WHERE uuid = '$SESSION_UUID';"
OUTPUT=$(echo "{\"session_id\": \"$SESSION_UUID\", \"tool_name\": \"Edit\", \"tool_input\": {}}" \
  | "$SCRIPTS_DIR/eits-pre-tool-use.sh" 2>/dev/null)
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
assert_eq "blocks Edit when no active todo" "deny" "$DECISION"

# Add active todo → should allow
db_query "INSERT INTO tasks (id, session_id, state_id, archived) VALUES (1, 1, 2, 0);"
db_query "INSERT INTO task_sessions (task_id, session_id) VALUES (1, 1);"
OUTPUT=$(echo "{\"session_id\": \"$SESSION_UUID\", \"tool_name\": \"Edit\", \"tool_input\": {}}" \
  | "$SCRIPTS_DIR/eits-pre-tool-use.sh" 2>/dev/null)
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
assert_eq "allows Edit when named session + active todo" "" "$DECISION"

# Write tool with active todo → allows (same rules as Edit)
OUTPUT=$(echo "{\"session_id\": \"$SESSION_UUID\", \"tool_name\": \"Write\", \"tool_input\": {}}" \
  | "$SCRIPTS_DIR/eits-pre-tool-use.sh" 2>/dev/null)
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
assert_eq "Write tool allowed when named session + active todo" "" "$DECISION"

# Write tool with no name → denies (same rules as Edit)
db_query "UPDATE sessions SET name = NULL WHERE uuid = '$SESSION_UUID';"
OUTPUT=$(echo "{\"session_id\": \"$SESSION_UUID\", \"tool_name\": \"Write\", \"tool_input\": {}}" \
  | "$SCRIPTS_DIR/eits-pre-tool-use.sh" 2>/dev/null)
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
assert_eq "Write tool denied when session has no name" "deny" "$DECISION"

# Spawned agent (parent_agent_id set) bypasses all checks
db_query "UPDATE agents SET parent_agent_id = 99 WHERE uuid = '$AGENT_UUID';"
OUTPUT=$(echo "{\"session_id\": \"$SESSION_UUID\", \"tool_name\": \"Edit\", \"tool_input\": {}}" \
  | "$SCRIPTS_DIR/eits-pre-tool-use.sh" 2>/dev/null)
DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
assert_eq "spawned agent bypasses all checks" "" "$DECISION"

cleanup_nats_mock
cleanup_db

# ---------------------------------------------------------------------------
# NATS publish payload shape
# ---------------------------------------------------------------------------
echo ""
echo "=== NATS publish payload shapes ==="

setup_nats_mock

# Log format: "nats pub <subject> <payload>"
# Fields: $1=nats $2=pub $3=subject $4+=payload

"$SCRIPTS_DIR/nats/publish-session-stop.sh" "test-uuid" "idle" 2>/dev/null
wait; sleep 0.5
NATS_CALL=$(tail -1 "$NATS_LOG" 2>/dev/null || echo "")
SUBJECT=$(echo "$NATS_CALL" | awk '{print $3}')
PAYLOAD=$(echo "$NATS_CALL" | cut -d' ' -f4-)
assert_eq "stop publishes to events.session.stop" "events.session.stop" "$SUBJECT"
NESTED_STATUS=$(echo "$PAYLOAD" | jq -r '.data.status' 2>/dev/null)
assert_eq "stop payload has data.status=idle" "idle" "$NESTED_STATUS"

"$SCRIPTS_DIR/nats/publish-session-compact.sh" "test-uuid" "compacting" 2>/dev/null
wait; sleep 0.5
NATS_CALL=$(tail -1 "$NATS_LOG" 2>/dev/null || echo "")
SUBJECT=$(echo "$NATS_CALL" | awk '{print $3}')
PAYLOAD=$(echo "$NATS_CALL" | cut -d' ' -f4-)
assert_eq "compact publishes to events.session.compact" "events.session.compact" "$SUBJECT"
NESTED_STATUS=$(echo "$PAYLOAD" | jq -r '.data.status' 2>/dev/null)
assert_eq "compact payload has data.status=compacting" "compacting" "$NESTED_STATUS"

"$SCRIPTS_DIR/nats/publish-session-start.sh" "test-uuid" "working" 2>/dev/null
wait; sleep 0.5
NATS_CALL=$(tail -1 "$NATS_LOG" 2>/dev/null || echo "")
SUBJECT=$(echo "$NATS_CALL" | awk '{print $3}')
assert_eq "start publishes to events.session.start" "events.session.start" "$SUBJECT"

cleanup_nats_mock

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo ""
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do
    echo "  - $e"
  done
  exit 1
fi

exit 0
