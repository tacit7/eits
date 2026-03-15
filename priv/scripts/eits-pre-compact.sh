#!/usr/bin/env bash
# Hook: Set session status to "compacting" before context compaction begins (PreCompact)
# Fires before Claude compacts the context window — lets the UI show why Claude is slow.
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
EITS_URL="${EITS_URL:-http://localhost:5000/api/v1}"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Set status to compacting so UI shows the reason for slow response
EITS_URL="$EITS_URL" eits sessions update "$session_id" --status compacting >/dev/null 2>&1 || true

# Publish to NATS
"$HOOK_DIR/nats/publish-session-compact.sh" "$session_id" "compacting"

# Notify user that context is being compacted
curl -sf ${EITS_API_KEY:+-H "Authorization: Bearer ${EITS_API_KEY}"} \
  -X POST "$EITS_URL/notifications" \
  -H "Content-Type: application/json" \
  -d "{\"title\":\"Context compacting\",\"body\":\"Session $session_id is compacting its context window.\",\"category\":\"agent\",\"resource_type\":\"session\",\"resource_id\":\"$session_id\"}" \
  > /dev/null 2>&1 || true

exit 0
