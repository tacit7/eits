#!/usr/bin/env bash
# Hook: Set session status to "idle" on Stop (Claude finished responding)
# Fires after every Claude turn completion, not just Ctrl+C.
# stop_hook_active guard prevents infinite loops.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Guard: if already inside a Stop hook invocation, exit immediately to prevent loops
stop_hook_active=$(echo "$input_json" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_hook_active="false"
[ "$stop_hook_active" = "true" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

BASE=${EITS_API_URL:-https://localhost:5001/api/v1}
_curl() { curl ${EITS_API_KEY:+-H "Authorization: Bearer ${EITS_API_KEY}"} "$@"; }

# Update session status to idle via REST (fire-and-forget)
_curl -sk -X PATCH "$BASE/sessions/$session_id" \
  -H 'Content-Type: application/json' \
  -d '{"status":"idle"}' >/dev/null 2>&1 &

# Publish to NATS
"$HOOK_DIR/nats/publish-session-stop.sh" "$session_id" "idle"

exit 0
