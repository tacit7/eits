#!/bin/bash

# Server availability guard (inlined — this hook lives outside priv/scripts/)
_eu="${EITS_URL:-http://localhost:5001/api/v1}"
_eu_scheme="${_eu%%://*}"; _eu="${_eu#*://}"; _eu="${_eu%%/*}"; _eu="${_eu##*@}"
if [[ "${_eu}" =~ ^(.*):([0-9]+)$ ]]; then
  _eu_h="${BASH_REMATCH[1]#[}"; _eu_h="${_eu_h%]}"; _eu_p="${BASH_REMATCH[2]}"
else
  _eu_h="${_eu#[}"; _eu_h="${_eu_h%]}"
  case "${_eu_scheme}" in https) _eu_p=443 ;; *) _eu_p=80 ;; esac
fi
(exec 3<>/dev/tcp/"${_eu_h}"/"${_eu_p}") 2>/dev/null || exit 0
unset _eu _eu_scheme _eu_h _eu_p

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

# Skip enforcement on spawn-only / orchestrator turns.
#
# Why: an orchestrator that only spawns sub-agents (Agent tool) and runs Bash/eits
# coordination calls shouldn't be forced to close its tracking task at every Stop —
# it's still coordinating. Only block Stop when this turn actually mutated files
# (Edit, Write, MultiEdit, NotebookEdit). If no edits happened since the last user
# turn boundary, exit 0.
#
# How: parse the transcript (JSONL) with jq; find the index of the most recent
# user-role entry, then scan assistant tool_use entries after it for file-editing
# tool names.
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  had_edit=$(jq -s -r '''
    (map(.type) | to_entries | map(select(.value == "user")) | last | .key // -1) as $u
    | .[($u+1):]
    | map(.message.content // [] | .[]? | select(.type == "tool_use") | .name)
    | flatten
    | any(. == "Edit" or . == "Write" or . == "MultiEdit" or . == "NotebookEdit")
  ''' "$TRANSCRIPT_PATH" 2>/dev/null)
  if [ "$had_edit" = "false" ]; then
    exit 0
  fi
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
