#!/usr/bin/env bash
# Hook: Track tool results after execution (PostToolUse)
# Publishes tool results to NATS for real-time Phoenix sync
set -uo pipefail

# --- EITS Workflow Guard ---
EITS_WORKFLOW="${EITS_WORKFLOW:-}"
if [ -z "$EITS_WORKFLOW" ]; then
  EITS_URL="${EITS_API_URL:-http://localhost:5000/api/v1}"
  ENABLED=$(curl -sf "${EITS_URL}/settings/eits_workflow_enabled" 2>/dev/null | jq -r '.enabled' 2>/dev/null || echo "true")
  [ "$ENABLED" = "false" ] && exit 0
elif [ "$EITS_WORKFLOW" = "0" ]; then
  exit 0
fi
# --- End Workflow Guard ---

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse stdin JSON for tool info
# Claude Code passes: {session_id, transcript_path, cwd, permission_mode, hook_event_name, tool_name, tool_input}
# PostToolUse gets the same fields as PreToolUse (tool_input contains what was sent to the tool)
input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Extract session_id from JSON input
session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

tool_name=$(echo "$input_json" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[ -z "$tool_name" ] && exit 0

# Extract tool_input (the arguments that were passed to the tool)
tool_input=$(echo "$input_json" | jq -c '.tool_input // {}' 2>/dev/null) || tool_input="{}"

# Publish tool completion to NATS
"$HOOK_DIR/nats/publish-tool-post.sh" "$session_id" "$tool_name" "$tool_input"

exit 0
