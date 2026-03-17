#!/usr/bin/env bash
# Hook: Set session status to "idle" on Stop (Claude finished responding)
# Fires after every Claude turn completion.
# stop_hook_active guard prevents infinite loops.
set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

stop_hook_active=$(echo "$input_json" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_hook_active="false"
[ "$stop_hook_active" = "true" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

eits sessions update "$session_id" --status idle >/dev/null 2>&1 &

exit 0
