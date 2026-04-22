#!/usr/bin/env bash
# Hook: Mark session status on SessionEnd based on entrypoint
# cli (interactive) → completed; sdk-cli (spawned/headless) → idle
# Also moves any in-progress tasks linked to this session to In Review (state_id=4)
set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"


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

# cli = interactive → completed; sdk-cli = spawned/headless → idle:session_ended
entrypoint="${CLAUDE_CODE_ENTRYPOINT:-}"
if [ "$entrypoint" = "cli" ]; then
  eits sessions update "$session_id" --status completed >/dev/null 2>&1 || true
else
  eits sessions update "$session_id" --status idle --reason session_ended >/dev/null 2>&1 || true
fi

exit 0
