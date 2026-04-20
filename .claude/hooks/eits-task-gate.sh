#!/bin/bash

# Server availability guard (inlined — this hook lives outside priv/scripts/)
_eu="${EITS_URL:-http://localhost:5001/api/v1}"; _eu="${_eu#http://}"; _eu="${_eu#https://}"; _eu="${_eu%%/*}"
(exec 3<>/dev/tcp/"${_eu%%:*}"/"${_eu##*:}") 2>/dev/null || exit 0; unset _eu

# eits-task-gate.sh
# Stop hook: blocks agent from stopping if it has in-progress EITS tasks.
# Fires on every Stop event. Reads EITS_AGENT_UUID from env.

INPUT=$(cat)

# Prevent infinite loop if stop hook itself is active
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Only applies to EITS agents
if [ -z "$EITS_AGENT_UUID" ]; then
  exit 0
fi

# Query in-progress tasks owned by this agent (agent_id FK, set on task creation).
# Using --agent instead of --session so we only see tasks this agent explicitly claimed,
# not historical session-task links that may reference unrelated sessions.
response=$(eits tasks list --agent "$EITS_AGENT_UUID" --state 2 2>/dev/null) || response=""

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
