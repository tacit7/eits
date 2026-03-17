#!/usr/bin/env bash
# Hook: Mark session as completed on SessionEnd
# Also moves any in-progress tasks linked to this session to In Review (state_id=4)
set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && exit 0

# Move any in-progress tasks linked to this session to In Review (state_id=4)
eits tasks list --session "$session_id" --state 2 2>/dev/null \
  | jq -r '.tasks[]?.id' \
  | while read -r task_id; do
      eits tasks update "$task_id" --state 4 >/dev/null 2>&1 || true
    done

# Mark session completed
eits sessions update "$session_id" --status completed >/dev/null 2>&1 || true

exit 0
