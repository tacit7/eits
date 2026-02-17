#!/usr/bin/env bash
# Publish post-tool event to NATS
# Args: $1 = session_id, $2 = tool_name, $3 = result/error (JSON)
set -euo pipefail

session_id="${1:-}"
tool_name="${2:-}"
result="${3:-{}}"

[ -z "$session_id" ] || [ -z "$tool_name" ] && exit 0

payload=$(jq -nc \
  --arg session_id "$session_id" \
  --arg tool_name "$tool_name" \
  --argjson result "$result" \
  '{session_id: $session_id, tool_name: $tool_name, result: $result}' 2>/dev/null) || exit 0

[ -z "$payload" ] && exit 0

nats pub "events.tool.post" "$payload" 2>/dev/null &
