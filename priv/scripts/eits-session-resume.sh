#!/bin/bash
# EITS Session Hook — resume
# Resolves session/agent/project via eits CLI and writes env vars to CLAUDE_ENV_FILE.

set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

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

# Resolve session info via eits CLI
SESSION_INFO=$(eits sessions get "$SESSION_ID" 2>/dev/null || true)

SESSION_INT_ID=""
AGENT_INT_ID=""
AGENT_ID=""
SESSION_NAME=""
PROJECT_ID=""

if [ -n "$SESSION_INFO" ]; then
  SESSION_INT_ID=$(echo "$SESSION_INFO" | jq -r '.id // empty')
  AGENT_INT_ID=$(echo "$SESSION_INFO" | jq -r '.agent_int_id // empty')
  AGENT_ID=$(echo "$SESSION_INFO" | jq -r '.agent_id // empty')
  SESSION_NAME=$(echo "$SESSION_INFO" | jq -r '.name // empty')
  PROJECT_ID=$(echo "$SESSION_INFO" | jq -r '.project_id // empty')
  _log "resolved: session_int=$SESSION_INT_ID agent_int=$AGENT_INT_ID agent_uuid=$AGENT_ID project_id=$PROJECT_ID"
else
  _log "WARN: eits sessions get failed, continuing with empty IDs"
fi

# Resolve project if not set on session
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(eits projects list 2>/dev/null | jq -r --arg path "$PROJECT_DIR" '.projects[]? | select(.path == $path) | .id' | head -1 || true)
  if [ -z "$PROJECT_ID" ]; then
    _log "project not found, creating: $PROJECT_NAME"
    PROJECT_ID=$(eits projects create --name "$PROJECT_NAME" --path "$PROJECT_DIR" 2>/dev/null | jq -r '.id // empty' || true)
    _log "project created: id=${PROJECT_ID:-FAILED}"
  else
    _log "project found by path: id=$PROJECT_ID"
  fi
fi

# Write env vars to CLAUDE_ENV_FILE
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  _log "env_file=$CLAUDE_ENV_FILE"
  _set() {
    local key="$1" val="$2"
    if grep -q "^export ${key}=" "$CLAUDE_ENV_FILE" 2>/dev/null; then
      sed -i '' "s|^export ${key}=.*|export ${key}=${val}|" "$CLAUDE_ENV_FILE"
      _log "updated $key=$val"
    else
      echo "export ${key}=${val}" >> "$CLAUDE_ENV_FILE"
      _log "wrote $key=$val"
    fi
  }

  [ -n "$ENTRYPOINT" ]     && _set "EITS_ENTRYPOINT" "$ENTRYPOINT"
  _set "EITS_SESSION_UUID" "$SESSION_ID"
  [ -n "$SESSION_INT_ID" ] && _set "EITS_SESSION_ID" "$SESSION_INT_ID"
  [ -n "$AGENT_INT_ID" ]   && _set "EITS_AGENT_ID" "$AGENT_INT_ID"
  [ -n "$AGENT_ID" ]       && _set "EITS_AGENT_UUID" "$AGENT_ID"
  [ -n "$PROJECT_ID" ]     && _set "EITS_PROJECT_ID" "$PROJECT_ID"

  _log "env vars written: SESSION_UUID=$SESSION_ID SESSION_ID=${SESSION_INT_ID:-} AGENT_ID=${AGENT_INT_ID:-} PROJECT_ID=${PROJECT_ID:-}"
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

# Patch entrypoint and mark session as working
[ -n "$ENTRYPOINT" ] && eits sessions update "$SESSION_ID" --entrypoint "$ENTRYPOINT" >/dev/null 2>&1 || true
eits sessions update "$SESSION_ID" --status "working" >/dev/null 2>&1 &

# Inject context
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
# Create + start in one shot (session linked automatically via EITS_SESSION_UUID)
eits tasks begin --title \"Task name\"

# Finish
eits tasks annotate <task_id> --body \"What happened\"
eits tasks update <task_id> --state 4

# Log commits
eits commits create --hash <hash>
\`\`\`"

echo "$CONTEXT"
