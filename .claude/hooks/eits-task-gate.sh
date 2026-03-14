#!/bin/bash
# eits-task-gate.sh
# Stop hook: blocks agent from stopping if it has in-progress EITS tasks.
# Fires on every Stop event. Reads EITS_SESSION_UUID from env.

INPUT=$(cat)

# Prevent infinite loop if stop hook itself is active
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Only applies to EITS sessions
if [ -z "$EITS_SESSION_UUID" ]; then
  exit 0
fi

EITS_PG_DB="${EITS_PG_DB:-eits_dev}"
EITS_PG_USER="${EITS_PG_USER:-postgres}"
EITS_PG_HOST="${EITS_PG_HOST:-localhost}"
export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"

# Query in-progress tasks linked to this session
TASKS=$(psql --no-psqlrc -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -t -A -F'|' -c "
  SELECT t.id, t.title
  FROM tasks t
  JOIN task_sessions ts ON ts.task_id = t.id
  JOIN sessions s ON s.id = ts.session_id
  WHERE s.uuid = '$EITS_SESSION_UUID'
    AND t.state_id = 2
    AND t.archived = false
  ORDER BY t.id
" 2>/dev/null)

if [ -z "$TASKS" ]; then
  exit 0
fi

echo "You have in-progress EITS tasks that must be moved to in-review before stopping:" >&2
echo "" >&2
while IFS='|' read -r task_id title; do
  echo "  Task #$task_id: $title" >&2
done <<< "$TASKS"
echo "" >&2
echo "Run for each task:" >&2
echo "  eits tasks annotate <task_id> --body 'Summary of what was done'" >&2
echo "  eits tasks update <task_id> --state 4" >&2

exit 2
