#!/usr/bin/env bash
# Hook: Set session status to "compacting" before context compaction begins (PreCompact)
# Fires before Claude compacts the context window — lets the UI show why Claude is slow.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="${EITS_URL:-http://localhost:5000/api/v1}"
_curl() { curl ${EITS_API_KEY:+-H "Authorization: Bearer ${EITS_API_KEY}"} "$@"; }

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Set status to compacting so UI shows the reason for slow response
"$HOOK_DIR/sql/postgresql/update-session-status.sh" "$session_id" "compacting"

# Publish to NATS
"$HOOK_DIR/nats/publish-session-compact.sh" "$session_id" "compacting"

# Notify user that context is being compacted
_curl -sf -X POST "$BASE_URL/notifications" \
  -H "Content-Type: application/json" \
  -d "{\"title\":\"Context compacting\",\"body\":\"Session $session_id is compacting its context window.\",\"category\":\"agent\",\"resource_type\":\"session\",\"resource_id\":\"$session_id\"}" \
  > /dev/null 2>&1 || true

exit 0
