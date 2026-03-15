#!/usr/bin/env bash
# Hook: Set session status to "idle" on Stop (Claude finished responding)
# Fires after every Claude turn completion, not just Ctrl+C.
# stop_hook_active guard prevents infinite loops.
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

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Guard: if already inside a Stop hook invocation, exit immediately to prevent loops
stop_hook_active=$(echo "$input_json" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_hook_active="false"
[ "$stop_hook_active" = "true" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Update session status to idle via eits CLI (fire-and-forget)
EITS_URL="${EITS_API_URL:-http://localhost:5000/api/v1}" eits sessions update "$session_id" --status idle >/dev/null 2>&1 &

# Publish to NATS
"$HOOK_DIR/nats/publish-session-stop.sh" "$session_id" "idle"

exit 0
