#!/usr/bin/env bash
# Hook: Set session status to "compacting" before context compaction begins (PreCompact)
# Fires before Claude compacts the context window — lets the UI show why Claude is slow.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Set status to compacting so UI shows the reason for slow response
"$HOOK_DIR/sql/update-session-status.sh" "$session_id" "compacting"

# Publish to NATS
"$HOOK_DIR/nats/publish-session-compact.sh" "$session_id" "compacting"

exit 0
