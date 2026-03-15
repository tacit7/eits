#!/usr/bin/env bash
# Hook: Set session status to "working" when user submits a prompt (UserPromptSubmit)
# Fires before Claude processes the prompt — marks the process as active.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Update session to working
"$HOOK_DIR/sql/postgresql/update-session-to-working.sh" "$session_id"

# Publish to NATS
"$HOOK_DIR/nats/publish-session-start.sh" "$session_id" "working"

exit 0
