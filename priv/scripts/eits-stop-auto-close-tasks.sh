#!/usr/bin/env bash
# Hook: Auto-close unclosed In Progress tasks at session end
# Runs AFTER eits-session-stop.sh in the Stop hook sequence.
# If any In Progress tasks remain (annotated but not marked Done),
# auto-closes them and sends a summary DM to session 4206 (team lead).
set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"

input_json=$(timeout 2 cat 2>/dev/null) || exit 0
[ -z "$input_json" ] && exit 0

session_id=$(echo "$input_json" | jq -r '.session_id // empty' 2>/dev/null) || exit 0
session_uuid=$(echo "$input_json" | jq -r '.session_uuid // empty' 2>/dev/null) || exit 0
[ -z "$session_id" ] && [ -z "$session_uuid" ] && exit 0

# Use session_id if we have it, otherwise fall back to UUID
_session_filter="${session_id:-$session_uuid}"

# Query for In Progress tasks (state_id = 2)
task_response=$(curl -sf --max-time 5 \
  "http://127.0.0.1:5001/api/v1/tasks?session_id=${_session_filter}&state_id=2&limit=200" \
  2>/dev/null) || exit 0

# Parse response — check if we got tasks
task_count=$(echo "$task_response" | jq -r '.tasks | length // 0' 2>/dev/null) || exit 0

if [ "$task_count" -eq 0 ]; then
  exit 0  # No In Progress tasks — nothing to do
fi

# Extract task IDs
task_ids=$(echo "$task_response" | jq -r '.tasks[].id // empty' 2>/dev/null) || exit 0

closed_count=0
closed_ids=()
failed_ids=()

# Auto-close each task
for task_id in $task_ids; do
  if eits tasks complete "$task_id" \
    --message "Auto-closed on session end (task #$task_id). Work was annotated but state was not updated to Done." \
    >/dev/null 2>&1; then
    ((closed_count++))
    closed_ids+=("$task_id")
  else
    failed_ids+=("$task_id")
  fi
done

# Send summary DM to session 4206 (team lead) only if any tasks were closed
if [ "$closed_count" -gt 0 ]; then
  # Join task IDs with comma-space separator
  task_ids_list=$(printf '%s, ' "${closed_ids[@]}" | sed 's/, $//')

  dm_body="Stop hook auto-closed ${closed_count} In Progress task(s) for session ${session_id}: ${task_ids_list}. Reason: annotated but state not updated to Done."

  eits dm --to 4206 --message "$dm_body" >/dev/null 2>&1 || true
fi

exit 0
