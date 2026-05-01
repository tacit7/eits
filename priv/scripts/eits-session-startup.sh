#!/bin/bash
# EITS Session Hook — startup / clear
# Writes env vars to CLAUDE_ENV_FILE and injects context.

set -uo pipefail

# --- EITS Workflow Guard ---
if [ "${EITS_WORKFLOW:-}" = "0" ]; then
  echo "EITS_WORKFLOW=0 — EITS integration disabled." >&2
  exit 0
fi
# --- End Workflow Guard ---

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"


LOG_FILE="${HOME}/.claude/hooks/eits.log"
_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [startup] $*" >> "$LOG_FILE" 2>/dev/null; }

# --- Load EITS_API_KEY from .env (overrides stale key in settings.json) ---
# The prod release .env is authoritative. If settings.json key drifts, this self-heals.
_EITS_DOT_ENV="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)/.env"
if [ -f "$_EITS_DOT_ENV" ]; then
  _DOT_ENV_KEY=$(grep '^EITS_API_KEY=' "$_EITS_DOT_ENV" | head -1 | cut -d= -f2-)
  [ -n "$_DOT_ENV_KEY" ] && export EITS_API_KEY="$_DOT_ENV_KEY"
fi
unset _EITS_DOT_ENV _DOT_ENV_KEY

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
MODEL=$(echo "$INPUT" | jq -r '.model // empty' 2>/dev/null || echo "")
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null || echo "")
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || echo "")
ENTRYPOINT="${CLAUDE_CODE_ENTRYPOINT:-}"

_log "--- session=$SESSION_ID model=${MODEL:-none} entrypoint=${ENTRYPOINT:-none} agent_id=${AGENT_ID:-none} agent_type=${AGENT_TYPE:-none}"
echo "[EITS] startup: session=$SESSION_ID entrypoint=${ENTRYPOINT:-none} agent_id=${AGENT_ID:-none} agent_type=${AGENT_TYPE:-none}" >&2

[ -z "$SESSION_ID" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_DIR")

_log "project_dir=$PROJECT_DIR env_file=${CLAUDE_ENV_FILE:-unset}"

# If running inside a worktree (.claude/worktrees/<name>), resolve project from
# the main project root — never create a separate project record for a worktree path.
LOOKUP_DIR="$PROJECT_DIR"
if [[ "$PROJECT_DIR" == *"/.claude/worktrees/"* ]]; then
  LOOKUP_DIR="${PROJECT_DIR%%/.claude/worktrees/*}"
  _log "worktree detected — using main project path for lookup: $LOOKUP_DIR"
  echo "[EITS] startup: worktree detected, resolving project from $LOOKUP_DIR" >&2
fi

# Check if session was pre-registered (spawned by workable task worker)
EXISTING_AGENT_UUID=""
EXISTING_AGENT_INT_ID=""
SESSION_INT_ID=""
SESSION_INFO=$(eits sessions get "$SESSION_ID" 2>/dev/null || true)
if [ -n "$SESSION_INFO" ]; then
  EXISTING_AGENT_UUID=$(echo "$SESSION_INFO" | jq -r '.agent_id // empty')
  EXISTING_AGENT_INT_ID=$(echo "$SESSION_INFO" | jq -r '.agent_int_id // empty')
  SESSION_INT_ID=$(echo "$SESSION_INFO" | jq -r '.id // empty')
  _log "session found: session_int=$SESSION_INT_ID agent_uuid=${EXISTING_AGENT_UUID:-none} agent_int_id=${EXISTING_AGENT_INT_ID:-none}"
  echo "[EITS] startup: pre-registered session_int=$SESSION_INT_ID agent_uuid=${EXISTING_AGENT_UUID:-none} agent_int_id=${EXISTING_AGENT_INT_ID:-none}" >&2
fi

# Resolve or create project using the canonical (non-worktree) path
PROJECT_ID=$(eits projects list 2>/dev/null | jq -r --arg path "$LOOKUP_DIR" '.projects[]? | select(.path == $path) | .id' | head -1 || true)
if [ -z "$PROJECT_ID" ]; then
  _log "project not found, creating: $(basename "$LOOKUP_DIR")"
  PROJECT_ID=$(eits projects create --name "$(basename "$LOOKUP_DIR")" --path "$LOOKUP_DIR" 2>/dev/null | jq -r '.id // empty' || true)
  _log "project created: id=${PROJECT_ID:-FAILED}"
else
  _log "project found: id=$PROJECT_ID"
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export EITS_URL=http://localhost:5001/api/v1"  >> "$CLAUDE_ENV_FILE"
  echo "export EITS_SESSION_UUID=$SESSION_ID"          >> "$CLAUDE_ENV_FILE"
  [ -n "$SESSION_INT_ID" ]          && echo "export EITS_SESSION_ID=$SESSION_INT_ID"           >> "$CLAUDE_ENV_FILE"
  [ -n "$ENTRYPOINT" ]              && echo "export EITS_ENTRYPOINT=$ENTRYPOINT"               >> "$CLAUDE_ENV_FILE"
  [ -n "$EXISTING_AGENT_UUID" ]     && echo "export EITS_AGENT_UUID=$EXISTING_AGENT_UUID"      >> "$CLAUDE_ENV_FILE"
  [ -n "$EXISTING_AGENT_INT_ID" ]   && echo "export EITS_AGENT_ID=$EXISTING_AGENT_INT_ID"      >> "$CLAUDE_ENV_FILE"
  [ -n "$PROJECT_ID" ]              && echo "export EITS_PROJECT_ID=$PROJECT_ID"               >> "$CLAUDE_ENV_FILE"
  # Propagate EITS_API_KEY so subsequent hooks (PostCompact, etc.) can authenticate API calls.
  # Use printf %q to safely escape the value — prevents metacharacters from corrupting the env file.
  [ -n "${EITS_API_KEY:-}" ]    && printf 'export EITS_API_KEY=%q\n' "$EITS_API_KEY"   >> "$CLAUDE_ENV_FILE"
  _log "env vars written — session_int=${SESSION_INT_ID:-none} agent_uuid=${EXISTING_AGENT_UUID:-none} agent_int_id=${EXISTING_AGENT_INT_ID:-none} project_id=${PROJECT_ID:-none}"
  echo "[EITS] startup: env written — session_int=${SESSION_INT_ID:-none} agent_uuid=${EXISTING_AGENT_UUID:-none} agent_int_id=${EXISTING_AGENT_INT_ID:-none} project_id=${PROJECT_ID:-none}" >&2

  # Patch entrypoint on pre-registered sessions
  if [ -n "$EXISTING_AGENT_UUID" ] && [ -n "$ENTRYPOINT" ]; then
    eits sessions update "$SESSION_ID" --entrypoint "$ENTRYPOINT" >/dev/null 2>&1 || true
    _log "patched entrypoint=$ENTRYPOINT on pre-registered session"
  fi
else
  _log "WARN: CLAUDE_ENV_FILE not set, skipping env writes"
fi

# Write session/agent UUIDs to .git/ for post-commit hook
GIT_DIR=$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null || true)
if [ -n "$GIT_DIR" ]; then
  echo "$SESSION_ID" > "$GIT_DIR/eits-session" 2>/dev/null || true
  [ -n "$EXISTING_AGENT_UUID" ] && echo "$EXISTING_AGENT_UUID" > "$GIT_DIR/eits-agent" 2>/dev/null || true
  _log "wrote git files"
fi

# Mark session as working and patch project_id so workers can resolve the path
_update_args=(--status "working")
[ -n "$PROJECT_ID" ] && _update_args+=(--project-id "$PROJECT_ID")
eits sessions update "$SESSION_ID" "${_update_args[@]}" >/dev/null 2>&1 &

# Drain pending annotations that failed (429) in a previous session.
# Uses direct curl (not eits tasks annotate) to avoid triggering the pending-log
# fallback inside annotate — that would double-write failed entries.
# Uses mkdir as a portable lock (atomic on macOS + Linux; flock is Linux-only).
_PENDING_LOG="${HOME}/.eits/pending-annotations.log"
_DRAIN_LOCK_DIR="${HOME}/.eits/pending-annotations.lock.d"
if [ -f "$_PENDING_LOG" ] && [ -s "$_PENDING_LOG" ]; then
  if mkdir "$_DRAIN_LOCK_DIR" 2>/dev/null; then
    trap 'rmdir "$_DRAIN_LOCK_DIR" 2>/dev/null' EXIT
    _log "draining pending annotations from $_PENDING_LOG"
    echo "[EITS] startup: draining pending annotations" >&2
    _tmp_log="${_PENDING_LOG}.processing.$$"
    mv "$_PENDING_LOG" "$_tmp_log"
    _failed_lines=()
    _ann_base_url="${EITS_URL:-http://localhost:5001/api/v1}"
    while IFS= read -r _line; do
      _task_id=$(echo "$_line" | jq -r '.task_id' 2>/dev/null)
      _body_val=$(echo "$_line" | jq -r '.body' 2>/dev/null)
      _title_val=$(echo "$_line" | jq -r '.title // ""' 2>/dev/null || echo "")
      # Re-queue unparseable lines rather than silently dropping them
      if [ -z "$_task_id" ] || [ -z "$_body_val" ]; then
        _log "drain: unparseable line, re-queuing: $_line"
        _failed_lines+=("$_line")
        continue
      fi
      _ann_payload=$(printf '{"body":%s,"title":%s}' \
        "$(printf '%s' "$_body_val" | jq -Rs .)" \
        "$(printf '%s' "$_title_val" | jq -Rs .)")
      _ann_status=$(curl -sk -o /dev/null -w '%{http_code}' -X POST \
        -H "Content-Type: application/json" \
        ${EITS_API_KEY:+-H "Authorization: Bearer $EITS_API_KEY"} \
        -d "$_ann_payload" \
        "$_ann_base_url/tasks/$_task_id/annotations")
      if [ "${_ann_status:-0}" -ge 200 ] && [ "${_ann_status:-0}" -lt 300 ]; then
        _log "drained annotation for task $_task_id"
      else
        _log "drain failed for task $_task_id (HTTP ${_ann_status:-?}), re-queuing"
        _failed_lines+=("$_line")
      fi
    done < "$_tmp_log"
    rm -f "$_tmp_log"
    # Write failures back once — avoids the double-write that `eits tasks annotate` would cause
    if [ ${#_failed_lines[@]} -gt 0 ]; then
      printf '%s\n' "${_failed_lines[@]}" >> "$_PENDING_LOG"
    fi
    rmdir "$_DRAIN_LOCK_DIR" 2>/dev/null
    trap - EXIT
  else
    _log "drain skipped: another session startup is already draining"
  fi
fi

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

if [ -n "$EXISTING_AGENT_UUID" ]; then
  INIT_NOTE="Session pre-registered (spawned agent). EITS_AGENT_UUID is already set — skip /eits-init."
  AGENT_UUID_LINE="**EITS_AGENT_UUID**: $EXISTING_AGENT_UUID (pre-registered)"
else
  INIT_NOTE="**IMPORTANT**: Immediately invoke the Skill tool with \`skill: \"eits-init\"\` before responding to the user or taking any other action."
  AGENT_UUID_LINE="**EITS_AGENT_UUID**: not yet set — available after /eits-init"
fi

CONTEXT="# Eye in the Sky Integration Active

$INIT_NOTE

## Session Context

- **EITS_SESSION_UUID**: $SESSION_ID
- **EITS_SESSION_ID**: ${SESSION_INT_ID:-unresolved}
- **EITS_PROJECT_ID**: ${PROJECT_ID:-unresolved}
- $AGENT_UUID_LINE

## Required Workflow (enforced by hooks)

**You MUST have a task In Progress before editing any files.**

\`\`\`bash
# After /eits-init — env vars EITS_AGENT_UUID, EITS_PROJECT_ID, EITS_SESSION_UUID are set

# Create + start in one shot
eits tasks begin --title \"Task name\"

# Finish (atomic: annotate + mark done in one round-trip)
eits tasks complete <task_id> --message \"What happened\"
# If complete fails, fall back to:
#   eits tasks annotate <task_id> --body \"What happened\"
#   eits tasks update <task_id> --state done

# Log commits
eits commits create --hash <hash>
\`\`\`

**Project**: $PROJECT_NAME ($PROJECT_TYPE)
**Path**: $PROJECT_DIR"

echo "$CONTEXT"
