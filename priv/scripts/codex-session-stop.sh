#!/usr/bin/env bash
# Codex Stop hook: set session status to "stopped" and enforce task annotation.
# Codex does not expose transcript_path, so annotation enforcement is simplified:
# blocks if an in-progress task exists with no annotation this turn.
set -uo pipefail
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

# Prevent infinite loops if stop hook itself triggers a stop
stop_hook_active=$(echo "$input_json" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_hook_active="false"
[ "$stop_hook_active" = "true" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# --- Task Annotation Enforcement ---
# Check for in-progress tasks linked to this session.
# Unlike the Claude version, we cannot inspect the transcript — enforcement
# is unconditional: if a task is in-progress, the agent must annotate before stopping.
in_progress=$(eits tasks list --session "$session_id" --state 2 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tasks = d.get('tasks', [])
    print('yes' if tasks else 'no')
except Exception:
    print('no')
" 2>/dev/null) || in_progress="no"

if [ "$in_progress" = "yes" ]; then
  echo "You have an in-progress EITS task but did not annotate it this turn. Run: eits tasks annotate <id> --body \"summary of what you did\" before finishing." >&2
  exit 2
fi
# --- End Task Annotation Enforcement ---

eits sessions update "$session_id" --status stopped >/dev/null 2>&1 &

exit 0
