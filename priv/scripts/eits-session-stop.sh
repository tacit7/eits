#!/usr/bin/env bash
# Hook: Set session status to "stopped" on Stop (Claude finished responding)
# Also enforces EITS task annotation when an in-progress task exists.
# Fires after every Claude turn completion.
# stop_hook_active guard prevents infinite loops.
set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"


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
  # Inspect last assistant turn: detect (a) whether real file-editing work happened,
  # and (b) whether an eits task annotation/update call was made.
  # If no mutating tools were used (read-only / DM-only turn), skip annotation requirement.
  # Detection is line-by-line to avoid false positives from string literals in heredocs.
  TURN_RESULT=$(TRANSCRIPT_PATH="$transcript_path" python3 - <<'PYEOF'
import sys, json, os, re

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

EITS_CMD = re.compile(
    r'(?:^|[;&|])\s*(?:EITS_\w+=\S+\s+)*eits\s+tasks?\s+(?:annotate|update|complete|done)\b',
    re.MULTILINE
)

# Tools that constitute "real work" requiring annotation.
# Bash is included because agents run eits/git/mix commands through it.
MUTATING_TOOLS = {'Write', 'Edit', 'MultiEdit', 'Bash', 'NotebookEdit'}

# Tools that are purely read-only or communication — do NOT require annotation.
READONLY_TOOLS = {'Read', 'Glob', 'Grep', 'WebFetch', 'WebSearch',
                  'ToolSearch', 'AskUserQuestion', 'SendMessage'}

def is_real_eits_call(cmd):
    for line in cmd.splitlines():
        stripped = line.strip()
        if stripped.startswith(("'eits", '"eits')):
            continue
        if EITS_CMD.search(line):
            return True
    return False

def is_dm_only_bash(cmd):
    """Return True if every eits call in this Bash command is a DM (not a task op)."""
    lines = cmd.splitlines()
    has_eits = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith(("'eits", '"eits')):
            continue
        # Any eits call that is NOT a dm is considered "real work"
        if re.search(r'(?:^|[;&|])\s*(?:EITS_\w+=\S+\s+)*eits\b', line, re.MULTILINE):
            has_eits = True
            if not re.search(r'(?:^|[;&|])\s*(?:EITS_\w+=\S+\s+)*eits\s+dm\b', line, re.MULTILINE):
                return False
    return has_eits  # True only if every eits call was a dm

task_annotated = False
has_mutating_work = False

# Walk backwards through entries: collect last assistant turn.
for entry in reversed(entries):
    if entry.get('type') == 'user' and not entry.get('toolUseResult'):
        break
    if entry.get('type') == 'assistant':
        content = entry.get('message', {}).get('content', [])
        if not isinstance(content, list):
            continue
        for block in content:
            if block.get('type') != 'tool_use':
                continue
            tool = block.get('name', '')
            if tool in READONLY_TOOLS:
                continue
            if tool == 'Bash':
                cmd = block.get('input', {}).get('command', '')
                if is_real_eits_call(cmd):
                    task_annotated = True
                # A Bash block that only sends DMs is not "mutating work"
                if not is_dm_only_bash(cmd):
                    has_mutating_work = True
            elif tool in MUTATING_TOOLS:
                has_mutating_work = True
            # Agent, ScheduleWakeup, etc. — treat as mutating
            elif tool not in READONLY_TOOLS:
                has_mutating_work = True

if task_annotated:
    print('annotated')
elif not has_mutating_work:
    print('readonly')
else:
    print('needs_annotation')
PYEOF
  )

  if [ "${TURN_RESULT:-}" = "annotated" ] || [ "${TURN_RESULT:-}" = "readonly" ]; then
    : # Either annotated or a read/DM-only turn — no gate needed
  else
    # Real work happened without an annotation. Only block if a task is actually in-progress.
    in_progress=$(eits tasks list --session "$session_id" --state 2 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tasks = d.get('tasks', [])
    print('yes' if tasks else 'no')
except Exception:
    print('no')
")

    if [ "$in_progress" = "yes" ]; then
      echo "You have an in-progress EITS task but did not annotate it this turn. Run: eits tasks annotate <id> --body \"summary of what you did\" before finishing." >&2
      exit 2
    fi
  fi
fi
# --- End Task Annotation Enforcement ---

eits sessions update "$session_id" --status idle >/dev/null 2>&1 &

exit 0
