#!/usr/bin/env bats
# Tests for priv/scripts/eits-session-startup.sh and eits-session-resume.sh
# Verifies env var injection and context output structure

STARTUP="$BATS_TEST_DIRNAME/../../priv/scripts/eits-session-startup.sh"
RESUME="$BATS_TEST_DIRNAME/../../priv/scripts/eits-session-resume.sh"
PRE_TOOL="$BATS_TEST_DIRNAME/../../priv/scripts/eits-pre-tool-use.sh"

# Real session with a name and agent in the DB
REAL_SESSION="b820f555-e03e-4900-baf7-8be15281a4e7"
TEST_SESSION_UUID="bats-hook-test-$(date +%s)"

setup() {
  TMPENV=$(mktemp)
  export CLAUDE_ENV_FILE="$TMPENV"
  export CLAUDE_PROJECT_DIR
  CLAUDE_PROJECT_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

teardown() {
  rm -f "$TMPENV"
}

# Helper: run hook and suppress stderr so $output is clean JSON
_startup() {
  local session="$1"
  local input; input=$(jq -n --arg sid "$session" '{session_id: $sid, model: "claude-sonnet-4-6"}')
  bash -c "echo '$input' | bash '$STARTUP' 2>/dev/null"
}

_resume() {
  local session="$1"
  local input; input=$(jq -n --arg sid "$session" '{session_id: $sid, model: "claude-sonnet-4-6"}')
  bash -c "echo '$input' | bash '$RESUME' 2>/dev/null"
}

# ── startup hook ──────────────────────────────────────────────────────────────

@test "startup: outputs valid JSON" {
  run _startup "$TEST_SESSION_UUID"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.continue == true' >/dev/null
}

@test "startup: sets suppressOutput true" {
  run _startup "$TEST_SESSION_UUID"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.suppressOutput == true' >/dev/null
}

@test "startup: hookSpecificOutput has hookEventName SessionStart" {
  run _startup "$TEST_SESSION_UUID"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
}

@test "startup: additionalContext contains session UUID" {
  run _startup "$TEST_SESSION_UUID"
  [ "$status" -eq 0 ]
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$context" =~ "$TEST_SESSION_UUID" ]]
}

@test "startup: additionalContext contains EITS_SESSION_UUID label" {
  run _startup "$TEST_SESSION_UUID"
  [ "$status" -eq 0 ]
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$context" =~ "EITS_SESSION_UUID" ]]
}

@test "startup: additionalContext contains EITS_PROJECT_ID label" {
  run _startup "$TEST_SESSION_UUID"
  [ "$status" -eq 0 ]
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$context" =~ "EITS_PROJECT_ID" ]]
}

@test "startup: additionalContext contains eits CLI workflow" {
  run _startup "$TEST_SESSION_UUID"
  [ "$status" -eq 0 ]
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$context" =~ "eits tasks create" ]]
}

@test "startup: additionalContext does not mention i-todo" {
  run _startup "$TEST_SESSION_UUID"
  [ "$status" -eq 0 ]
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ ! "$context" =~ "i-todo" ]]
}

@test "startup: writes EITS_SESSION_UUID to CLAUDE_ENV_FILE" {
  _startup "$TEST_SESSION_UUID" >/dev/null 2>&1
  grep -q "EITS_SESSION_UUID=$TEST_SESSION_UUID" "$TMPENV"
}

@test "startup: writes EITS_URL to CLAUDE_ENV_FILE" {
  _startup "$TEST_SESSION_UUID" >/dev/null 2>&1
  grep -q "EITS_URL=" "$TMPENV"
}

@test "startup: writes EITS_PROJECT_ID to CLAUDE_ENV_FILE" {
  _startup "$TEST_SESSION_UUID" >/dev/null 2>&1
  grep -q "EITS_PROJECT_ID=" "$TMPENV"
}

@test "startup: exits cleanly with empty session_id" {
  run bash -c "echo '{}' | bash '$STARTUP' 2>/dev/null"
  [ "$status" -eq 0 ]
}

# ── resume hook ───────────────────────────────────────────────────────────────

@test "resume: outputs valid JSON for known session" {
  run _resume "$REAL_SESSION"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.continue == true' >/dev/null
}

@test "resume: additionalContext contains EITS_AGENT_UUID label" {
  run _resume "$REAL_SESSION"
  [ "$status" -eq 0 ]
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$context" =~ "EITS_AGENT_UUID" ]]
}

@test "resume: additionalContext contains EITS_PROJECT_ID label" {
  run _resume "$REAL_SESSION"
  [ "$status" -eq 0 ]
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$context" =~ "EITS_PROJECT_ID" ]]
}

@test "resume: additionalContext contains eits CLI workflow" {
  run _resume "$REAL_SESSION"
  [ "$status" -eq 0 ]
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$context" =~ "eits tasks create" ]]
}

@test "resume: additionalContext does not mention i-todo" {
  run _resume "$REAL_SESSION"
  [ "$status" -eq 0 ]
  context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ ! "$context" =~ "i-todo" ]]
}

@test "resume: writes EITS_AGENT_UUID to CLAUDE_ENV_FILE" {
  _resume "$REAL_SESSION" >/dev/null 2>&1
  grep -q "EITS_AGENT_UUID=" "$TMPENV"
}

@test "resume: EITS_AGENT_UUID in env file is a UUID" {
  _resume "$REAL_SESSION" >/dev/null 2>&1
  agent_uuid=$(grep "^EITS_AGENT_UUID=" "$TMPENV" | cut -d= -f2)
  [[ "$agent_uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

@test "resume: writes EITS_PROJECT_ID to CLAUDE_ENV_FILE" {
  _resume "$REAL_SESSION" >/dev/null 2>&1
  grep -q "EITS_PROJECT_ID=" "$TMPENV"
}

@test "resume: exits cleanly with empty session_id" {
  run bash -c "echo '{}' | bash '$RESUME' 2>/dev/null"
  [ "$status" -eq 0 ]
}

# ── pre-tool-use hook ─────────────────────────────────────────────────────────

@test "pre-tool-use: denies edit when session has no name" {
  unknown="00000000-0000-0000-0000-000000000000"
  input=$(jq -n --arg sid "$unknown" --arg tool "Edit" '{session_id: $sid, tool_name: $tool}')
  run bash -c "echo '$input' | bash '$PRE_TOOL' 2>/dev/null"
  [ "$status" -eq 0 ]
  decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision')
  [ "$decision" = "deny" ]
}

@test "pre-tool-use: denial for no-name session does not mention i-todo" {
  unknown="00000000-0000-0000-0000-000000000000"
  input=$(jq -n --arg sid "$unknown" --arg tool "Write" '{session_id: $sid, tool_name: $tool}')
  run bash -c "echo '$input' | bash '$PRE_TOOL' 2>/dev/null"
  [ "$status" -eq 0 ]
  reason=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
  [[ ! "$reason" =~ "i-todo" ]]
}

@test "pre-tool-use: denial for no-active-todo references eits tasks" {
  # Use a session with a name but ensure its tasks are filtered (use REAL_SESSION)
  # The hook checks active todos — if none in progress it denies with eits CLI message
  input=$(jq -n --arg sid "$REAL_SESSION" --arg tool "Edit" '{session_id: $sid, tool_name: $tool}')
  run bash -c "echo '$input' | bash '$PRE_TOOL' 2>/dev/null"
  [ "$status" -eq 0 ]
  # If denied for no active todo, reason should reference eits not i-todo
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    reason=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
    [[ ! "$reason" =~ "i-todo" ]]
    [[ "$reason" =~ "eits tasks" ]]
  fi
}

@test "pre-tool-use: exits cleanly with empty input" {
  run bash -c "echo '' | bash '$PRE_TOOL' 2>/dev/null"
  [ "$status" -eq 0 ]
}
