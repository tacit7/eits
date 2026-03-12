#!/usr/bin/env bash
# Hook: Enforce EITS session and todo requirements before file edits (PreToolUse)
# Matcher: Edit|Write — only runs on file modification tools
# Returns hookSpecificOutput JSON for structured denial; exit 2 for hard errors
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EITS_PG_DB="${EITS_PG_DB:-eits_dev}"
EITS_PG_USER="${EITS_PG_USER:-postgres}"
EITS_PG_HOST="${EITS_PG_HOST:-localhost}"
export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"
_pgq() { psql --no-psqlrc -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -t -A -c "$1" 2>/dev/null; }

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

tool_name=$(echo "$input_json" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ -z "$tool_name" ] && exit 0

# Resolve integer session ID for error messages
session_int_id=$(_pgq "SELECT id FROM sessions WHERE uuid = '$session_id' LIMIT 1" || true)
session_ref="${session_int_id:-$session_id}"

# Skip spawned agents — they don't need /eits-init
is_spawned=$(_pgq "SELECT 1 FROM sessions s JOIN agents a ON a.id = s.agent_id WHERE s.uuid = '$session_id' AND a.parent_agent_id IS NOT NULL LIMIT 1" || true)

if [ -z "$is_spawned" ]; then
  # Check session has been named via /eits-init
  session_name=$(_pgq "SELECT name FROM sessions WHERE uuid = '$session_id' AND name IS NOT NULL AND name != '' LIMIT 1" || true)

  if [ -z "$session_name" ]; then
    jq -n \
      --arg reason "Session has no name. Run /eits-init before doing any work. Session: $session_ref" \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: $reason
        }
      }'
    exit 0
  fi

  # Check for active EITS todo before allowing edits
  if ! "$HOOK_DIR/sql/postgresql/check-active-todo.sh" "$session_id"; then
    jq -n \
      --arg reason "No active EITS todo for session $session_ref. Workflow: (1) i-todo create --title \"Task\" (2) i-todo start --task_id <id> (3) i-todo add-session --task_id <id> --session_id $session_id (4) do work (5) i-todo status --task_id <id> --state_id 4 to move to In Review when done" \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: $reason
        }
      }'
    exit 0
  fi
fi

exit 0
