#!/usr/bin/env bash
# Hook: Track tool usage before execution (PreToolUse)
# Publishes tool calls to NATS for real-time Phoenix sync
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse stdin JSON for tool info
# Claude Code passes: {session_id, transcript_path, cwd, permission_mode, hook_event_name, tool_name, tool_input}
input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Extract session_id from JSON input (not environment variable)
session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Resolve integer session ID for error messages
EITS_DB="$HOME/.config/eye-in-the-sky/eits.db"
session_int_id=$(sqlite3 "$EITS_DB" "SELECT id FROM sessions WHERE uuid = '$session_id' LIMIT 1;" 2>/dev/null || true)
session_ref="${session_int_id:-$session_id}"

tool_name=$(echo "$input_json" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ -z "$tool_name" ] && exit 0

# Extract tool_input (not tool_params)
tool_input=$(echo "$input_json" | jq -c '.tool_input // {}' 2>/dev/null) || tool_input="{}"

# Only block the Edit tool — all other tools pass through freely
if [ "$tool_name" = "Edit" ]; then
  # Check session has been named via /eits-init (skip spawned agents)
  is_spawned=$(sqlite3 "$EITS_DB" \
    "SELECT 1 FROM sessions s JOIN agents a ON a.id = s.agent_id WHERE s.uuid = '$session_id' AND a.parent_agent_id IS NOT NULL LIMIT 1;" \
    2>/dev/null || true)
  if [ -z "$is_spawned" ]; then
    session_name=$(sqlite3 "$EITS_DB" \
      "SELECT name FROM sessions WHERE uuid = '$session_id' AND name IS NOT NULL AND name != '' LIMIT 1;" \
      2>/dev/null || true)
    if [ -z "$session_name" ]; then
      cat >&2 <<EOF
Error: Session has no name. Run /eits-init before doing any work.

Session: $session_ref
EOF
      exit 2
    fi
  fi

  # Check for active EITS todo before allowing edits
  if ! "$HOOK_DIR/sql/check-active-todo.sh" "$session_id"; then
    cat >&2 <<EOF
Error: No active EITS todo found for this session.

Required actions:
0. Initialize session first: /eits-init (if not done yet)
1. Create a todo: i-todo create --title "Task name" --description "Details"
2. Start the todo: i-todo start --task_id <uuid> --session_id $session_ref

Session: $session_ref
EOF
    exit 2
  fi
fi

# Publish all tool calls to NATS
"$HOOK_DIR/nats/publish-tool-pre.sh" "$session_id" "$tool_name" "$tool_input"

# Publish EITS domain tools to NATS (input-dependent, fire-and-forget)
# Matches both Phoenix (eye-in-the-sky) and Go fallback (eits-go) server prefixes
case "$tool_name" in
  mcp__eye-in-the-sky__i-commits|mcp__eits-go__i-commits)
    payload=$(echo "$tool_input" | jq -c \
      --arg agent_id "$session_id" \
      '{agent_id: $agent_id, commit_hashes: .commit_hashes, commit_messages: .commit_messages}')
    "$HOOK_DIR/nats/publish-domain-event.sh" "commits" "$payload"
    ;;
  mcp__eye-in-the-sky__i-note-add|mcp__eits-go__i-note-add)
    payload=$(echo "$tool_input" | jq -c '{parent_type, parent_id, body, title, starred}')
    "$HOOK_DIR/nats/publish-domain-event.sh" "notes" "$payload"
    ;;
  mcp__eye-in-the-sky__i-save-session-context|mcp__eits-go__i-save-session-context)
    payload=$(echo "$tool_input" | jq -c \
      --arg agent_id "$session_id" \
      '{agent_id: $agent_id, context: .context}')
    "$HOOK_DIR/nats/publish-domain-event.sh" "session.context" "$payload"
    ;;
  mcp__eye-in-the-sky__i-todo|mcp__eits-go__i-todo)
    payload=$(printf '%s' "$tool_input" | jq -c '{command, task_id, title, description, priority, tags}' 2>/dev/null) || true
    [ -n "$payload" ] && "$HOOK_DIR/nats/publish-domain-event.sh" "todo" "$payload"
    ;;
esac

exit 0
