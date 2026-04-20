#!/usr/bin/env bash
# Hook: Enforce EITS session and todo requirements before file edits (PreToolUse)
# Matcher: Edit|Write — only runs on file modification tools
# Returns hookSpecificOutput JSON for structured denial; exit 0 to allow
set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"


input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

tool_name=$(echo "$input_json" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ -z "$tool_name" ] && exit 0

# Fetch session info via eits CLI (single call: id, name, is_spawned)
session_info=$(eits sessions get "$session_id" 2>/dev/null) || session_info=""

if [ -z "$session_info" ]; then
  # API unreachable — fail open so work isn't blocked
  exit 0
fi

is_spawned=$(echo "$session_info" | jq -r '.is_spawned // false')
session_ref=$(echo "$session_info" | jq -r '.id // empty')
session_ref="${session_ref:-$session_id}"

if [ "$is_spawned" != "true" ]; then
  # Check session has been named via /eits-init
  session_name=$(echo "$session_info" | jq -r '.name // empty')

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
  active_count=$(eits tasks list --session "$session_id" --state 2 --limit 200 2>/dev/null | jq -r '.tasks | length' 2>/dev/null || echo "0")
  if [ "${active_count:-0}" -eq 0 ]; then
    jq -n \
      --arg reason "No active EITS todo for session $session_ref. Run: eits tasks begin --title \"Task name\" (creates, links, and starts in one shot). Complete with: eits tasks update <id> --state 4" \
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
