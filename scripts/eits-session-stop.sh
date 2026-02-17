#!/usr/bin/env bash
# Hook: Set session status to "waiting" on Stop (Ctrl+C, interrupt)
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse stdin JSON for session info
input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Extract session_id from JSON input
session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Update session status to waiting (SQL)
"$HOOK_DIR/sql/update-session-status.sh" "$session_id" "waiting"

# Publish to NATS
"$HOOK_DIR/nats/publish-session-stop.sh" "$session_id" "waiting"

exit 0
