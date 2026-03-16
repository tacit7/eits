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

# Query in-progress tasks linked to this session via eits CLI
response=$(eits tasks list --session "$EITS_SESSION_UUID" --state 2 2>/dev/null) || response=""

if [ -z "$response" ]; then
  exit 0
fi

task_count=$(echo "$response" | jq -r '.tasks | length' 2>/dev/null) || task_count=0

if [ "${task_count:-0}" -eq 0 ]; then
  exit 0
fi

echo "You have in-progress EITS tasks that must be moved to in-review before stopping:" >&2
echo "" >&2
echo "$response" | jq -r '.tasks[] | "  Task #\(.id): \(.title)"' >&2
echo "" >&2
echo "Run for each task:" >&2
echo "  eits tasks annotate <task_id> --body 'Summary of what was done'" >&2
echo "  eits tasks update <task_id> --state 4" >&2

exit 2
