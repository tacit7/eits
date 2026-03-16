#!/bin/bash
# EITS Session Hook — resume
# Resolves integer IDs from API and overwrites env vars in CLAUDE_ENV_FILE.

set -uo pipefail

# --- EITS Workflow Guard ---
EITS_WORKFLOW="${EITS_WORKFLOW:-}"
if [ -z "$EITS_WORKFLOW" ]; then
  EITS_URL="${EITS_API_URL:-http://localhost:5000/api/v1}"
  ENABLED=$(curl -sf "${EITS_URL}/settings/eits_workflow_enabled" 2>/dev/null | jq -r '.enabled' 2>/dev/null || echo "true")
  [ "$ENABLED" = "false" ] && exit 0
elif [ "$EITS_WORKFLOW" = "0" ]; then
  exit 0
fi
# --- End Workflow Guard ---

EITS_PG_DB="${EITS_PG_DB:-eits_dev}"
EITS_PG_USER="${EITS_PG_USER:-postgres}"
EITS_PG_HOST="${EITS_PG_HOST:-localhost}"
export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"
_pgq() { psql -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -t -A --no-psqlrc -c "$1" 2>/dev/null | grep -v '^Time:'; }

MAPPING_FILE="$HOME/.claude/hooks/session_agent_map.json"
EITS_BASE="${EITS_API_URL:-http://localhost:5000/api/v1}"
_curl() { curl ${EITS_API_KEY:+-H "Authorization: Bearer ${EITS_API_KEY}"} "$@"; }
LOG_FILE="${HOME}/.claude/hooks/eits.log"
_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [resume] $*" >> "$LOG_FILE" 2>/dev/null; }

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
MODEL=$(echo "$INPUT" | jq -r '.model // empty' 2>/dev/null || echo "")
ENTRYPOINT="${CLAUDE_CODE_ENTRYPOINT:-}"

_log "--- session=$SESSION_ID model=${MODEL:-none} entrypoint=${ENTRYPOINT:-none}"
echo "[EITS] resume: session=$SESSION_ID entrypoint=${ENTRYPOINT:-none}" >&2

[ -z "$SESSION_ID" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_DIR")
PROJECT_DIR_SQL="${PROJECT_DIR//\'/\'\'}"
PROJECT_NAME_SQL="${PROJECT_NAME//\'/\'\'}"

# Resolve integer IDs — API first, psql fallback
SESSION_INT_ID=""
AGENT_INT_ID=""
AGENT_ID=""

_log "resolving IDs via API: $EITS_BASE/sessions/$SESSION_ID"
SESSION_INFO=$(_curl -sf "$EITS_BASE/sessions/$SESSION_ID" 2>/dev/null || true)

if [ -n "$SESSION_INFO" ] && echo "$SESSION_INFO" | jq -e '.initialized == true' >/dev/null 2>&1; then
  SESSION_INT_ID=$(echo "$SESSION_INFO" | jq -r '.id // empty')
  AGENT_INT_ID=$(echo "$SESSION_INFO" | jq -r '.agent_int_id // empty')
  AGENT_ID=$(echo "$SESSION_INFO" | jq -r '.agent_id // empty')
  _log "resolved via API: session_int=$SESSION_INT_ID agent_int=$AGENT_INT_ID agent_uuid=$AGENT_ID"
  echo "[EITS] resume resolved via API: session=$SESSION_INT_ID agent=$AGENT_INT_ID" >&2
else
  _log "API failed or session not initialized, falling back to psql"
  SESSION_INT_ID=$(_pgq "SELECT id FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1" || true)
  EXISTING_AGENT=$(_pgq "SELECT agent_id FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1" || true)
  if [ -n "$EXISTING_AGENT" ]; then
    AGENT_INT_ID="$EXISTING_AGENT"
    AGENT_ID=$(_pgq "SELECT uuid FROM agents WHERE id = $EXISTING_AGENT LIMIT 1" || true)
  fi
  _log "resolved via psql: session_int=${SESSION_INT_ID:-empty} agent_int=${AGENT_INT_ID:-empty} agent_uuid=${AGENT_ID:-empty}"
  echo "[EITS] resume resolved via psql: session=$SESSION_INT_ID agent=$AGENT_INT_ID" >&2
fi

# Update mapping file
if [ -n "$AGENT_ID" ]; then
  if [ -f "$MAPPING_FILE" ]; then
    UPDATED=$(jq --arg sid "$SESSION_ID" --arg aid "$AGENT_ID" '.[$sid] = $aid' "$MAPPING_FILE" 2>/dev/null)
  else
    UPDATED=$(jq -n --arg sid "$SESSION_ID" --arg aid "$AGENT_ID" '{($sid): $aid}')
  fi
  echo "$UPDATED" > "$MAPPING_FILE"
fi

# Overwrite env vars — resume always wins over startup
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  _log "env_file=$CLAUDE_ENV_FILE"
  _set() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "$CLAUDE_ENV_FILE" 2>/dev/null; then
      sed -i '' "s|^${key}=.*|${key}=${val}|" "$CLAUDE_ENV_FILE"
      _log "updated $key=$val"
    else
      echo "${key}=${val}" >> "$CLAUDE_ENV_FILE"
      _log "wrote $key=$val"
    fi
  }

  [ -n "$ENTRYPOINT" ] && _set "EITS_ENTRYPOINT" "$ENTRYPOINT"
  _set "EITS_SESSION_UUID" "$SESSION_ID"
  if [ -n "${SESSION_INT_ID:-}" ]; then
    _set "EITS_SESSION_ID" "$SESSION_INT_ID"
  else
    _log "WARN: SESSION_INT_ID empty, skipping EITS_SESSION_ID update"
  fi
  if [ -n "${AGENT_INT_ID:-}" ]; then
    _set "EITS_AGENT_ID" "$AGENT_INT_ID"
  else
    _log "WARN: AGENT_INT_ID empty, skipping EITS_AGENT_ID update"
  fi
  if [ -n "${AGENT_ID:-}" ]; then
    _set "EITS_AGENT_UUID" "$AGENT_ID"
    _log "wrote EITS_AGENT_UUID=$AGENT_ID"
  else
    _log "WARN: AGENT_ID (UUID) empty, skipping EITS_AGENT_UUID update"
  fi

  # Resolve project by path and set EITS_PROJECT_ID
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
    _set "EITS_PROJECT_ID" "$PROJECT_ID"
    _pgq "UPDATE sessions SET project_id = $PROJECT_ID WHERE uuid = '$SESSION_ID' AND project_id IS NULL" >/dev/null || true
    _log "updated sessions.project_id=$PROJECT_ID for uuid=$SESSION_ID"
  else
    _log "WARN: project_id not resolved, skipping"
  fi

  # Patch entrypoint on resumed session
  if [ -n "$ENTRYPOINT" ]; then
    curl -sf -X PATCH -H "Content-Type: application/json" \
      -d "{\"entrypoint\":\"$ENTRYPOINT\"}" \
      "${EITS_BASE}/sessions/${SESSION_ID}" >/dev/null 2>&1 || true
    _log "patched entrypoint=$ENTRYPOINT"
  fi

  echo "[EITS] env vars updated: SESSION_UUID=$SESSION_ID SESSION_ID=${SESSION_INT_ID:-} AGENT_ID=${AGENT_INT_ID:-} PROJECT_ID=${PROJECT_ID:-}" >&2
else
  _log "WARN: CLAUDE_ENV_FILE not set, skipping env writes"
fi

# Write session/agent UUIDs to .git/ for post-commit hook
GIT_DIR=$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null || true)
if [ -n "$GIT_DIR" ]; then
  echo "$SESSION_ID" > "$GIT_DIR/eits-session" 2>/dev/null || true
  _log "wrote session UUID to $GIT_DIR/eits-session"
  if [ -n "${AGENT_ID:-}" ]; then
    echo "$AGENT_ID" > "$GIT_DIR/eits-agent" 2>/dev/null || true
    _log "wrote agent UUID to $GIT_DIR/eits-agent"
  fi
fi

# NATS (fire-and-forget)
DESCRIPTION=$(_pgq "SELECT description FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1" || true)
SESSION_NAME=$(_pgq "SELECT name FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1" || true)

nats pub "events.session.start" "$(jq -nc \
  --arg session_id "$SESSION_ID" \
  --arg agent_id "${AGENT_ID:-$SESSION_ID}" \
  --arg description "${DESCRIPTION:-}" \
  --arg name "${SESSION_NAME:-}" \
  --arg project_name "$PROJECT_NAME" \
  --arg model "${MODEL:-}" \
  --arg provider "claude" \
  --arg worktree_path "$PROJECT_DIR" \
  '{session_id: $session_id, agent_id: $agent_id, description: $description, name: $name, project_name: $project_name, model: $model, provider: $provider, worktree_path: $worktree_path}')" 2>/dev/null &

nats pub "events.session.update" "$(jq -nc \
  --arg session_id "$SESSION_ID" \
  --arg status "working" \
  '{session_id: $session_id, status: $status}')" 2>/dev/null &

# Inject context with session info
CONTEXT="# Eye in the Sky — Session Resumed

## Session Context

- **EITS_SESSION_UUID**: $SESSION_ID
- **EITS_AGENT_UUID**: ${AGENT_ID:-unresolved}
- **EITS_PROJECT_ID**: ${PROJECT_ID:-unresolved}
- **Session**: ${SESSION_NAME:-unnamed} (ID: ${SESSION_INT_ID:-$SESSION_ID})
- **Project**: $PROJECT_NAME

Call \`/eits-init\` if this session needs a name, otherwise continue your work.

## Workflow

\`\`\`bash
# Create + start (session linked automatically via EITS_SESSION_UUID)
eits tasks create --title \"Task name\" --description \"Details\"
eits tasks start <task_id>

# Finish
eits tasks annotate <task_id> --body \"What happened\"
eits tasks update <task_id> --state 4

# Log commits
eits commits create --hash <hash>
\`\`\`"

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
