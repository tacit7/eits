#!/usr/bin/env bash
# Codex UserPromptSubmit hook: set session status to "working"
# Fires before Codex processes each user prompt — keeps EITS dashboard current.
set -uo pipefail
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

eits sessions update "$session_id" --status working >/dev/null 2>&1 &

exit 0
