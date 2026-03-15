#!/usr/bin/env bash
# Hook: Set session status to "working" on SessionStart
set -uo pipefail

[ "${EITS_WORKFLOW:-1}" = "0" ] && exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse stdin JSON for session info
input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Extract session_id from JSON input
session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Update session to working via eits CLI (fire-and-forget)
EITS_URL="${EITS_API_URL:-http://localhost:5000/api/v1}" eits sessions update "$session_id" --status working >/dev/null 2>&1 &

# Publish to NATS
"$HOOK_DIR/nats/publish-session-start.sh" "$session_id" "working"

exit 0
