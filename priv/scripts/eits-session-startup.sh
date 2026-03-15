#!/bin/bash
# EITS Session Hook — startup / clear / compact
# Writes env vars to CLAUDE_ENV_FILE and injects /eits-init prompt.

set -uo pipefail

[ "${EITS_WORKFLOW:-1}" = "0" ] && exit 0

EITS_PG_DB="${EITS_PG_DB:-eits_dev}"
EITS_PG_USER="${EITS_PG_USER:-postgres}"
EITS_PG_HOST="${EITS_PG_HOST:-localhost}"
export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"
_pgq() { psql -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -t -A --no-psqlrc -c "$1" 2>/dev/null | grep -v '^Time:'; }

EITS_BASE="${EITS_API_URL:-http://localhost:5000/api/v1}"
LOG_FILE="${HOME}/.claude/hooks/eits.log"
_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [startup] $*" >> "$LOG_FILE" 2>/dev/null; }

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
MODEL=$(echo "$INPUT" | jq -r '.model // empty' 2>/dev/null || echo "")
ENTRYPOINT="${CLAUDE_CODE_ENTRYPOINT:-}"

_log "--- session=$SESSION_ID model=${MODEL:-none} entrypoint=${ENTRYPOINT:-none}"
echo "[EITS] startup: session=$SESSION_ID entrypoint=${ENTRYPOINT:-none}" >&2

[ -z "$SESSION_ID" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_DIR")
PROJECT_DIR_SQL="${PROJECT_DIR//\'/\'\'}"
PROJECT_NAME_SQL="${PROJECT_NAME//\'/\'\'}"

_log "project_dir=$PROJECT_DIR env_file=${CLAUDE_ENV_FILE:-unset}"

PROJECT_ID=""
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "EITS_URL=http://localhost:5000/api/v1" >> "$CLAUDE_ENV_FILE"
  [ -n "${EITS_API_KEY:-}" ] && echo "EITS_API_KEY=${EITS_API_KEY}" >> "$CLAUDE_ENV_FILE"
  echo "EITS_SESSION_UUID=$SESSION_ID" >> "$CLAUDE_ENV_FILE"
  _log "wrote EITS_SESSION_UUID=$SESSION_ID"
  [ -n "$ENTRYPOINT" ] && echo "EITS_ENTRYPOINT=$ENTRYPOINT" >> "$CLAUDE_ENV_FILE" && _log "wrote EITS_ENTRYPOINT=$ENTRYPOINT"

  # Check if this session was pre-registered (e.g. by workable task worker)
  # If so, inject EITS_AGENT_UUID so eits-init skips interactive prompting
  EXISTING_AGENT_UUID=$(_pgq "SELECT a.uuid FROM agents a JOIN sessions s ON s.agent_id = a.id WHERE s.uuid = '$SESSION_ID' LIMIT 1" || true)
  if [ -n "$EXISTING_AGENT_UUID" ]; then
    echo "EITS_AGENT_UUID=$EXISTING_AGENT_UUID" >> "$CLAUDE_ENV_FILE"
    _log "pre-registered session: wrote EITS_AGENT_UUID=$EXISTING_AGENT_UUID"
    # Patch entrypoint on pre-registered sessions
    if [ -n "$ENTRYPOINT" ]; then
      curl -sf -X PATCH -H "Content-Type: application/json" \
        -d "{\"entrypoint\":\"$ENTRYPOINT\"}" \
        "${EITS_BASE}/sessions/${SESSION_ID}" >/dev/null 2>&1 || true
      _log "patched entrypoint=$ENTRYPOINT on pre-registered session"
    fi
  fi

  # Resolve or create project
  PROJECT_ID=$(_pgq "SELECT id FROM projects WHERE path = '$PROJECT_DIR_SQL' LIMIT 1" || true)
  if [ -z "$PROJECT_ID" ]; then
    _log "project not found, creating: $PROJECT_NAME"
    PROJECT_ID=$(_pgq "
      INSERT INTO projects (name, path, active, inserted_at, updated_at)
      VALUES ('$PROJECT_NAME_SQL', '$PROJECT_DIR_SQL', true, NOW(), NOW())
      RETURNING id
    " || true)
    _log "project created: id=${PROJECT_ID:-FAILED}"
  else
    _log "project found: id=$PROJECT_ID"
  fi

  if [ -n "$PROJECT_ID" ]; then
    echo "EITS_PROJECT_ID=$PROJECT_ID" >> "$CLAUDE_ENV_FILE"
    _log "wrote EITS_PROJECT_ID=$PROJECT_ID"
  else
    _log "WARN: project_id not resolved, skipping"
  fi
else
  _log "WARN: CLAUDE_ENV_FILE not set, skipping env writes"
fi

# Write session/agent UUIDs to .git/ for post-commit hook
GIT_DIR=$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null || true)
if [ -n "$GIT_DIR" ]; then
  echo "$SESSION_ID" > "$GIT_DIR/eits-session" 2>/dev/null || true
  _log "wrote session UUID to $GIT_DIR/eits-session"
  if [ -n "${EXISTING_AGENT_UUID:-}" ]; then
    echo "$EXISTING_AGENT_UUID" > "$GIT_DIR/eits-agent" 2>/dev/null || true
    _log "wrote agent UUID to $GIT_DIR/eits-agent"
  fi
fi

# NATS (fire-and-forget)
nats pub "events.session.start" "$(jq -nc \
  --arg session_id "$SESSION_ID" \
  --arg project_name "$PROJECT_NAME" \
  --arg model "${MODEL:-}" \
  --arg provider "claude" \
  --arg worktree_path "$PROJECT_DIR" \
  '{session_id: $session_id, project_name: $project_name, model: $model, provider: $provider, worktree_path: $worktree_path}')" 2>/dev/null &

nats pub "events.session.update" "$(jq -nc \
  --arg session_id "$SESSION_ID" \
  --arg status "working" \
  '{session_id: $session_id, status: $status}')" 2>/dev/null &

# Build project type string
if [ -f "$PROJECT_DIR/mix.exs" ]; then
  PROJECT_TYPE="Elixir/Phoenix"
elif [ -f "$PROJECT_DIR/package.json" ]; then
  PROJECT_TYPE="Node.js"
elif [ -f "$PROJECT_DIR/go.mod" ]; then
  PROJECT_TYPE="Go Module"
else
  PROJECT_TYPE="Git Repository"
fi

if [ -n "${EXISTING_AGENT_UUID:-}" ]; then
  INIT_NOTE="Session pre-registered (spawned agent). EITS_AGENT_UUID is already set — skip /eits-init."
  AGENT_UUID_LINE="**EITS_AGENT_UUID**: $EXISTING_AGENT_UUID (pre-registered)"
else
  INIT_NOTE="**IMPORTANT**: Call \`/eits-init\` to name and describe your session."
  AGENT_UUID_LINE="**EITS_AGENT_UUID**: not yet set — available after /eits-init"
fi

CONTEXT="# Eye in the Sky Integration Active

$INIT_NOTE

## Session Context

- **EITS_SESSION_UUID**: $SESSION_ID
- **EITS_PROJECT_ID**: ${PROJECT_ID:-unresolved}
- $AGENT_UUID_LINE

## Required Workflow (enforced by hooks)

**You MUST have a task In Progress before editing any files.**

\`\`\`bash
# After /eits-init — env vars EITS_AGENT_UUID, EITS_PROJECT_ID, EITS_SESSION_UUID are set

# Create + start (start also calls link-session as a follow-up)
eits tasks create --title \"Task name\" --description \"Details\"
eits tasks start <task_id>
# Or atomically: eits tasks quick --title \"Task name\" --description \"Details\"

# Finish
eits tasks annotate <task_id> --body \"What happened\"
eits tasks update <task_id> --state 4

# Log commits
eits commits create --hash <hash>
\`\`\`

**Project**: $PROJECT_NAME ($PROJECT_TYPE)
**Path**: $PROJECT_DIR"

cat <<EOF
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $(printf '%s\n' "$CONTEXT" | jq -Rs .)
  }
}
EOF
