#!/usr/bin/env bash
# Hook: Enforce EITS session and todo requirements before file edits (PreToolUse)
# Matcher: Edit|Write — only runs on file modification tools
# Returns hookSpecificOutput JSON for structured denial; exit 2 for hard errors
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EITS_DB="${EITS_DB_PATH:-$HOME/.config/eye-in-the-sky/eits.db}"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

tool_name=$(echo "$input_json" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ -z "$tool_name" ] && exit 0

# Resolve integer session ID for error messages
session_int_id=$(sqlite3 "$EITS_DB" "SELECT id FROM sessions WHERE uuid = '$session_id' LIMIT 1;" 2>/dev/null || true)
session_ref="${session_int_id:-$session_id}"

# Skip spawned agents — they don't need /eits-init
is_spawned=$(sqlite3 "$EITS_DB" \
  "SELECT 1 FROM sessions s JOIN agents a ON a.id = s.agent_id WHERE s.uuid = '$session_id' AND a.parent_agent_id IS NOT NULL LIMIT 1;" \
  2>/dev/null || true)

if [ -z "$is_spawned" ]; then
  # Check session has been named via /eits-init
  session_name=$(sqlite3 "$EITS_DB" \
    "SELECT name FROM sessions WHERE uuid = '$session_id' AND name IS NOT NULL AND name != '' LIMIT 1;" \
    2>/dev/null || true)

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
  if ! "$HOOK_DIR/sql/check-active-todo.sh" "$session_id"; then
    jq -n \
      --arg reason "No active EITS todo for session $session_ref. Create one with: i-todo create --title \"Task name\" then i-todo start --task_id <id>" \
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
