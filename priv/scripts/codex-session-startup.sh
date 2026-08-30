#!/usr/bin/env bash
# Codex SessionStart hook: register/resolve the EITS session and persist Codex
# session identity for later CLI calls.

set -uo pipefail

[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/eits-lib.sh"

LOG_FILE="${HOME}/.claude/hooks/eits.log"
_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [codex-startup] $*" >> "$LOG_FILE" 2>/dev/null; }

HOOK_ENTRYPOINT="${ENTRYPOINT:-}"

_EITS_DOT_ENV="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd)/.env"
if [ -f "$_EITS_DOT_ENV" ]; then
  _DOT_ENV_KEY=$(grep '^EITS_API_KEY=' "$_EITS_DOT_ENV" | head -1 | cut -d= -f2-)
  [ -n "$_DOT_ENV_KEY" ] && export EITS_API_KEY="$_DOT_ENV_KEY"
fi
unset _EITS_DOT_ENV _DOT_ENV_KEY

load_codex_env() {
  local env_file="${EITS_CODEX_ENV_FILE:-}"

  if [ -z "$env_file" ]; then
    local session_ref="${EITS_CODEX_SESSION_ID:-${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-}}}"
    [ -n "$session_ref" ] && env_file="$HOME/.eits/codex/sessions/$session_ref.env"
  fi

  [ -f "$env_file" ] || return 0
  # shellcheck disable=SC1090
  . "$env_file"
}

load_codex_env

INPUT=$(timeout 2 cat 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
MODEL=$(echo "$INPUT" | jq -r '.model // empty' 2>/dev/null || echo "")
HOOK_SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null || echo "")

[ -z "$SESSION_ID" ] && SESSION_ID="${CODEX_THREAD_ID:-${CODEX_SESSION_ID:-${EITS_SESSION_UUID:-}}}"
[ -z "$MODEL" ] && MODEL="${EITS_MODEL:-}"
[ -z "$SESSION_ID" ] && exit 0

SESSION_ENTRYPOINT="${EITS_ENTRYPOINT:-cli}"
PROCESS_ENTRYPOINT="${HOOK_ENTRYPOINT:-cli}"
PROJECT_DIR="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
PROJECT_NAME=$(basename "$PROJECT_DIR")

LOOKUP_DIR="$PROJECT_DIR"
if [[ "$PROJECT_DIR" == *"/.claude/worktrees/"* ]]; then
  LOOKUP_DIR="${PROJECT_DIR%%/.claude/worktrees/*}"
elif [[ "$PROJECT_DIR" == *"/.codex/worktrees/"* ]]; then
  LOOKUP_DIR="${PROJECT_DIR%%/.codex/worktrees/*}"
fi

_log "--- session=$SESSION_ID model=${MODEL:-none} source=${HOOK_SOURCE:-none} project_dir=$PROJECT_DIR"

EXISTING_AGENT_UUID=""
EXISTING_AGENT_INT_ID=""
SESSION_INT_ID=""
SESSION_PROJECT_ID=""

load_session_info() {
  local info
  if ! info=$(eits sessions get "$SESSION_ID" 2>/dev/null); then
    return 1
  fi

  SESSION_INT_ID=$(echo "$info" | jq -r '.id // empty' 2>/dev/null || echo "")
  [ -n "$SESSION_INT_ID" ] || return 1

  EXISTING_AGENT_UUID=$(echo "$info" | jq -r '.agent_id // empty' 2>/dev/null || echo "")
  EXISTING_AGENT_INT_ID=$(echo "$info" | jq -r '.agent_int_id // empty' 2>/dev/null || echo "")
  SESSION_PROJECT_ID=$(echo "$info" | jq -r '.project_id // empty' 2>/dev/null || echo "")
  return 0
}

if load_session_info; then
  _log "session found: session_int=$SESSION_INT_ID agent_uuid=${EXISTING_AGENT_UUID:-none} agent_int_id=${EXISTING_AGENT_INT_ID:-none}"
else
  _log "session not found, auto-registering: $SESSION_ID"
  create_args=(
    sessions create
    --session-id "$SESSION_ID"
    --project "$PROJECT_NAME"
    --project-path "$LOOKUP_DIR"
  )
  [ -n "$MODEL" ] && create_args+=(--model "$MODEL")
  [ -n "$SESSION_ENTRYPOINT" ] && create_args+=(--entrypoint "$SESSION_ENTRYPOINT")

  if CREATE_RESULT=$(eits "${create_args[@]}" 2>/dev/null); then
    SESSION_INT_ID=$(echo "$CREATE_RESULT" | jq -r '.id // empty' 2>/dev/null || echo "")
    EXISTING_AGENT_UUID=$(echo "$CREATE_RESULT" | jq -r '.agent_uuid // empty' 2>/dev/null || echo "")
    EXISTING_AGENT_INT_ID=$(echo "$CREATE_RESULT" | jq -r '.agent_id // empty' 2>/dev/null || echo "")
    _log "auto-registered: session_int=${SESSION_INT_ID:-none} agent_uuid=${EXISTING_AGENT_UUID:-none} agent_int_id=${EXISTING_AGENT_INT_ID:-none}"
  else
    _log "auto-register command failed for $SESSION_ID"
    load_session_info || true
  fi
fi

PROJECT_ID="${SESSION_PROJECT_ID:-}"
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(eits projects list 2>/dev/null | jq -r --arg path "$LOOKUP_DIR" '.projects[]? | select(.path == $path) | .id' | head -1 || true)
fi

if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(eits projects create --name "$PROJECT_NAME" --path "$LOOKUP_DIR" 2>/dev/null | jq -r '.id // empty' || true)
fi

write_codex_env_file() {
  local env_dir="${HOME}/.eits/codex"
  local sessions_dir="$env_dir/sessions"
  local safe_session_id
  safe_session_id=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9_.-' '_')

  mkdir -p "$sessions_dir" 2>/dev/null || return 0
  chmod 700 "$env_dir" "$sessions_dir" 2>/dev/null || true

  local tmp_file
  tmp_file=$(mktemp "$env_dir/session.env.XXXXXX") || return 0
  chmod 600 "$tmp_file" 2>/dev/null || true

  {
    printf 'export EITS_URL=%q\n' "${EITS_URL:-http://localhost:5001/api/v1}"
    printf 'export EITS_SESSION_UUID=%q\n' "$SESSION_ID"
    printf 'export EITS_CODEX_SESSION_ID=%q\n' "$SESSION_ID"
    [ -n "$SESSION_INT_ID" ] && printf 'export EITS_SESSION_ID=%q\n' "$SESSION_INT_ID"
    [ -n "$PROCESS_ENTRYPOINT" ] && printf 'export ENTRYPOINT=%q\n' "$PROCESS_ENTRYPOINT"
    [ -n "$EXISTING_AGENT_UUID" ] && printf 'export EITS_AGENT_UUID=%q\n' "$EXISTING_AGENT_UUID"
    [ -n "$EXISTING_AGENT_INT_ID" ] && printf 'export EITS_AGENT_ID=%q\n' "$EXISTING_AGENT_INT_ID"
    [ -n "$PROJECT_ID" ] && printf 'export EITS_PROJECT_ID=%q\n' "$PROJECT_ID"
  } > "$tmp_file"

  cp "$tmp_file" "$sessions_dir/$safe_session_id.env" 2>/dev/null || true
  chmod 600 "$sessions_dir/$safe_session_id.env" 2>/dev/null || true
  rm -f "$tmp_file"
  _log "wrote codex env file: $sessions_dir/$safe_session_id.env"
}

write_codex_env_file

GIT_DIR=$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null || true)
if [ -n "$GIT_DIR" ]; then
  echo "$SESSION_ID" > "$GIT_DIR/eits-session" 2>/dev/null || true
  [ -n "$EXISTING_AGENT_UUID" ] && echo "$EXISTING_AGENT_UUID" > "$GIT_DIR/eits-agent" 2>/dev/null || true
fi

update_args=(--status idle)
[ -n "$PROJECT_ID" ] && update_args+=(--project-id "$PROJECT_ID")
[ -n "$MODEL" ] && update_args+=(--model "$MODEL")
[ -n "$SESSION_ENTRYPOINT" ] && update_args+=(--entrypoint "$SESSION_ENTRYPOINT")
eits sessions update "$SESSION_ID" "${update_args[@]}" >/dev/null 2>&1 &

if [ -f "$PROJECT_DIR/mix.exs" ]; then
  PROJECT_TYPE="Elixir/Phoenix"
elif [ -f "$PROJECT_DIR/package.json" ]; then
  PROJECT_TYPE="Node.js"
elif [ -f "$PROJECT_DIR/go.mod" ]; then
  PROJECT_TYPE="Go Module"
else
  PROJECT_TYPE="Git Repository"
fi

if [ -n "$EXISTING_AGENT_UUID" ]; then
  INIT_NOTE="Session registered. EITS_AGENT_UUID is set — /eits-init is not needed."
  AGENT_UUID_LINE="**EITS_AGENT_UUID**: $EXISTING_AGENT_UUID"
else
  INIT_NOTE="**IMPORTANT**: Auto-registration failed (EITS server may be down). Invoke \`skill: \"eits-init\"\` before responding to the user."
  AGENT_UUID_LINE="**EITS_AGENT_UUID**: not set — auto-registration failed"
fi

cat <<EOF
# Eye in the Sky Integration Active

$INIT_NOTE

## Session Context

- **EITS_SESSION_UUID**: $SESSION_ID
- **EITS_SESSION_ID**: ${SESSION_INT_ID:-unresolved}
- **EITS_PROJECT_ID**: ${PROJECT_ID:-unresolved}
- $AGENT_UUID_LINE

## Required Workflow (enforced by hooks)

**You MUST have a task In Progress before editing any files.**

\`\`\`bash
eits tasks begin --title "Task name"
eits dm inbox --since-session --team-only --json
eits tasks complete <task_id> --message "What happened"
eits commits create --hash <hash>
\`\`\`

**Project**: $PROJECT_NAME ($PROJECT_TYPE)
**Path**: $PROJECT_DIR
EOF
