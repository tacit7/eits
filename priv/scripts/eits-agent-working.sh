#!/usr/bin/env bash
# Hook: Set session status to "working" on SessionStart
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE=${EITS_API_URL:-https://localhost:5001/api/v1}
_curl() { curl ${EITS_API_KEY:+-H "Authorization: Bearer ${EITS_API_KEY}"} "$@"; }

# Parse stdin JSON for session info
input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Extract session_id from JSON input
session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Update session to working via REST
_curl -sk -X PATCH "$BASE/sessions/$session_id" \
  -H 'Content-Type: application/json' \
  -d '{"status":"working"}' >/dev/null 2>&1 &

# Publish to NATS
"$HOOK_DIR/nats/publish-session-start.sh" "$session_id" "working"

exit 0
