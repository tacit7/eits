#!/usr/bin/env bash
# Publish pre-tool event to NATS
# Args: $1 = session_id, $2 = tool_name, $3 = tool_input (JSON)
set -euo pipefail

session_id="${1:-}"
tool_name="${2:-}"
tool_input="${3:-{}}"

[ -z "$session_id" ] || [ -z "$tool_name" ] && exit 0

payload=$(jq -nc \
  --arg session_id "$session_id" \
  --arg tool_name "$tool_name" \
  --argjson tool_input "$tool_input" \
  '{session_id: $session_id, tool_name: $tool_name, tool_input: $tool_input}' 2>/dev/null) || exit 0

[ -z "$payload" ] && exit 0

nats pub "events.tool.pre" "$payload" 2>/dev/null &
