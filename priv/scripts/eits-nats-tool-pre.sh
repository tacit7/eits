#!/usr/bin/env bash
# Hook: Publish all tool calls to NATS before execution (async, non-blocking)
# Runs on every PreToolUse via async hook config
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

tool_name=$(echo "$input_json" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ -z "$tool_name" ] && exit 0

tool_input=$(echo "$input_json" | jq -c '.tool_input // {}' 2>/dev/null) || tool_input="{}"

# Publish all tool calls to NATS
"$HOOK_DIR/nats/publish-tool-pre.sh" "$session_id" "$tool_name" "$tool_input"

# Publish EITS domain tools to NATS (input-dependent)
# Matches all known server name prefixes for Phoenix HTTP MCP (eits-web, eye-in-the-sky)
case "$tool_name" in
  Edit|Write)
    file_path=$(echo "$tool_input" | jq -r '.file_path // empty' 2>/dev/null) || file_path=""
    if [ -n "$file_path" ]; then
      action=$([ "$tool_name" = "Write" ] && echo "Writing" || echo "Editing")
      basename=$(basename "$file_path")
      "$HOOK_DIR/sql/update-session-intent.sh" "$session_id" "$action $basename"
    fi
    ;;
  mcp__eits-web__i-commits|mcp__eye-in-the-sky__i-commits)
    payload=$(echo "$tool_input" | jq -c \
      --arg agent_id "$session_id" \
      '{agent_id: $agent_id, commit_hashes: .commit_hashes, commit_messages: .commit_messages}')
    "$HOOK_DIR/nats/publish-domain-event.sh" "commits" "$payload"
    ;;
  mcp__eits-web__i-note-add|mcp__eye-in-the-sky__i-note-add)
    payload=$(echo "$tool_input" | jq -c '{parent_type, parent_id, body, title, starred}')
    "$HOOK_DIR/nats/publish-domain-event.sh" "notes" "$payload"
    ;;
  mcp__eits-web__i-save-session-context|mcp__eye-in-the-sky__i-save-session-context)
    payload=$(echo "$tool_input" | jq -c \
      --arg agent_id "$session_id" \
      '{agent_id: $agent_id, context: .context}')
    "$HOOK_DIR/nats/publish-domain-event.sh" "session.context" "$payload"
    ;;
  mcp__eits-web__i-todo|mcp__eye-in-the-sky__i-todo)
    payload=$(printf '%s' "$tool_input" | jq -c '{command, task_id, title, description, priority, tags}' 2>/dev/null) || true
    [ -n "$payload" ] && "$HOOK_DIR/nats/publish-domain-event.sh" "todo" "$payload"
    ;;
esac

exit 0
