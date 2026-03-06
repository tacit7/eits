#!/usr/bin/env bash
# Hook: Set session status to "working" on SessionStart
# Uses SQLite directly (Go MCP server version)
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse stdin JSON for session info
input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Extract session_id from JSON input
session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Update session to working (SQL - only if not already working)
"$HOOK_DIR/sql/update-session-to-working.sh" "$session_id"

# Publish to NATS
"$HOOK_DIR/nats/publish-session-start.sh" "$session_id" "working"

exit 0
