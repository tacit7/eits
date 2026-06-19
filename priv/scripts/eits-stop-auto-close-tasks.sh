#!/usr/bin/env bash
# Hook: Auto-close any in-progress EITS tasks when a session's Stop hook fires.
# Runs after eits-session-stop.sh. Prevents tasks from getting stuck in-progress
# when an sdk-cli agent finishes without explicitly completing them.
set -uo pipefail

[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

stop_hook_active=$(echo "$input_json" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_hook_active="false"
[ "$stop_hook_active" = "true" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Find in-progress tasks (state 2) for this session
task_ids=$(eits tasks list --session "$session_id" --state 2 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    for t in d.get('tasks', []):
        print(t['id'])
except Exception:
    pass
" 2>/dev/null) || exit 0

[ -z "$task_ids" ] && exit 0

while IFS= read -r task_id; do
    [ -z "$task_id" ] && continue
    eits tasks complete "$task_id" --message "Auto-closed at session stop." >/dev/null 2>&1 || true
done <<< "$task_ids"

exit 0
