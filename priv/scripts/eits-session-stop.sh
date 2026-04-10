#!/usr/bin/env bash
# Hook: Set session status to "stopped" on Stop (Claude finished responding)
# Also enforces EITS task annotation when an in-progress task exists.
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

# --- EITS Task Annotation Enforcement ---
# Only block if an in-progress EITS task exists AND the agent didn't annotate it this turn.
transcript_path=$(echo "$input_json" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  # Check if last assistant turn contained an eits task annotation/update call
  TASK_UPDATED=$(TRANSCRIPT_PATH="$transcript_path" python3 - <<'PYEOF'
import sys, json, os

transcript_path = os.environ.get('TRANSCRIPT_PATH', '')
try:
    lines = open(transcript_path).readlines()
except Exception:
    sys.exit(0)

entries = []
for line in lines:
    line = line.strip()
    if not line:
        continue
    try:
        entries.append(json.loads(line))
    except Exception:
        continue

# Walk backwards through entries: collect last assistant turn.
# Stop when we hit a real human prompt (type=user without toolUseResult).
for entry in reversed(entries):
    if entry.get('type') == 'user' and not entry.get('toolUseResult'):
        break
    if entry.get('type') == 'assistant':
        content = entry.get('message', {}).get('content', [])
        if not isinstance(content, list):
            continue
        for block in content:
            if block.get('type') != 'tool_use' or block.get('name') != 'Bash':
                continue
            cmd = block.get('input', {}).get('command', '')
            if any(x in cmd for x in [
                'eits tasks annotate',
                'eits tasks update',
                'eits tasks complete',
                'eits tasks done',
            ]):
                print('found')
                sys.exit(0)
PYEOF
  )

  if [ "${TASK_UPDATED:-}" != "found" ]; then
    # Only enforce if an in-progress task is linked to this session
    in_progress=$(eits tasks list --session "${EITS_SESSION_UUID:-}" --state 2 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tasks = d.get('tasks', [])
    print('yes' if tasks else 'no')
except Exception:
    print('no')
")

    if [ "$in_progress" = "yes" ]; then
      printf '{"decision":"block","reason":"You have an in-progress EITS task but did not annotate it this turn. Run: eits tasks annotate <id> --body \"summary of what you did\" before finishing."}'
      exit 2
    fi
  fi
fi
# --- End Task Annotation Enforcement ---

eits sessions update "$session_id" --status stopped >/dev/null 2>&1 &

exit 0
