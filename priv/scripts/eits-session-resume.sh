#!/bin/bash
# EITS Session Hook — resume
# Resolves session/agent/project via eits CLI and writes env vars to CLAUDE_ENV_FILE.

set -uo pipefail

# --- EITS Workflow Guard ---
[ "${EITS_WORKFLOW:-}" = "0" ] && exit 0
# --- End Workflow Guard ---

. "$(cd "$(dirname "$0")" && pwd)/eits-lib.sh"


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

# Patch entrypoint and mark session status. Codex resume should stay idle until
# UserPromptSubmit marks it busy.
_session_start_status="${EITS_SESSION_START_STATUS:-working}"
[ -n "$ENTRYPOINT" ] && eits sessions update "$SESSION_ID" --entrypoint "$ENTRYPOINT" >/dev/null 2>&1 || true
eits sessions update "$SESSION_ID" --status "$_session_start_status" >/dev/null 2>&1 &

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
eits tasks complete <task_id> --message \"What happened\"
# If complete fails, fall back to:
#   eits tasks annotate <task_id> --body \"What happened\"
#   eits tasks update <task_id> --state done

# Log commits
eits commits create --hash <hash>
\`\`\`"

echo "$CONTEXT"

# --- Channel Resume Context Injection ---
# Inject recent channel messages from channels where this session was @mentioned
# in the last hour. Skips pure ambient-observer channels (no direct mention).
# Only runs when we have a numeric session ID and psql is available.

_inject_channel_context() {
  local session_int="$1"
  local session_uuid="$2"

  [ -z "$session_int" ] && return

  local psql_bin
  psql_bin=$(command -v psql 2>/dev/null) || psql_bin="/opt/homebrew/bin/psql"
  [ -x "$psql_bin" ] || { _log "psql not found, skipping channel context"; return; }

  export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"
  local pg_user="${EITS_PG_USER:-postgres}"
  local pg_host="${EITS_PG_HOST:-localhost}"
  local pg_db="${EITS_PG_DB:-eits_dev}"

  # Query: channels where this session is a member AND was @mentioned in last hour.
  # For each qualifying channel, return the 3 most recent messages (chronological order).
  local sql
  sql="
WITH mentioned_channels AS (
  SELECT DISTINCT m.channel_id
  FROM messages m
  JOIN channel_members cm ON cm.channel_id = m.channel_id
  WHERE cm.session_id = ${session_int}
    AND m.channel_id IS NOT NULL
    AND m.inserted_at > NOW() - INTERVAL '1 hour'
    AND m.session_id != ${session_int}
    AND (
      m.body ILIKE '%@${session_int}%'
      OR m.body ILIKE '%@${session_uuid}%'
    )
),
recent_msgs AS (
  SELECT
    c.id    AS channel_id,
    c.name  AS channel_name,
    REPLACE(REPLACE(m.body, E'\n', ' '), E'\r', '') AS body,
    COALESCE(s.name, 'session:' || m.session_id::text) AS from_name,
    to_char(m.inserted_at AT TIME ZONE 'UTC', 'HH24:MI') AS ts,
    ROW_NUMBER() OVER (PARTITION BY m.channel_id ORDER BY m.id DESC) AS rn
  FROM mentioned_channels mc
  JOIN channels c ON c.id = mc.channel_id
  JOIN messages m ON m.channel_id = mc.channel_id
  LEFT JOIN sessions s ON s.id = m.session_id
)
SELECT channel_id, channel_name, from_name, ts, body
FROM recent_msgs
WHERE rn <= 3
ORDER BY channel_id, rn DESC;
"

  local rows
  rows=$("$psql_bin" --no-psqlrc -U "$pg_user" -h "$pg_host" -d "$pg_db" \
    -t -A -F $'\x1f' -c "$sql" 2>/dev/null || true)

  [ -z "$rows" ] && return

  # Group rows by channel and format output
  local output=""
  local current_channel_id=""
  local current_channel_name=""

  while IFS=$'\x1f' read -r ch_id ch_name from_name ts body; do
    [ -z "$ch_id" ] && continue

    if [ "$ch_id" != "$current_channel_id" ]; then
      current_channel_id="$ch_id"
      current_channel_name="$ch_name"
      output="${output}
### #${ch_name} (channel:${ch_id})"
    fi

    # Truncate body to 200 chars to keep context lean
    local short_body="${body:0:200}"
    [ "${#body}" -gt 200 ] && short_body="${short_body}…"

    output="${output}
- **${from_name}** [${ts}]: ${short_body}"
  done <<< "$rows"

  if [ -n "$output" ]; then
    echo ""
    echo "## Recent Channel Activity (last 1h — you were @mentioned)"
    echo "$output"
    _log "injected channel context: $(echo "$rows" | wc -l | tr -d ' ') messages"
  fi
}

_inject_channel_context "${SESSION_INT_ID:-}" "${SESSION_ID:-}"

# --- Notification Buffer Flush ---
# Summarise pending channel notifications buffered during idle window.
# These are MSG prompts queued by AgentWorker that haven't been delivered yet.
# Showing the count + senders on resume lets the agent orient before AgentWorker
# delivers the full prompts. TTL = 1 hour (same as channel context window).

_inject_pending_notifications() {
  local session_int="$1"

  [ -z "$session_int" ] && return

  local psql_bin
  psql_bin=$(command -v psql 2>/dev/null) || psql_bin="/opt/homebrew/bin/psql"
  [ -x "$psql_bin" ] || return

  export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"
  local pg_user="${EITS_PG_USER:-postgres}"
  local pg_host="${EITS_PG_HOST:-localhost}"
  local pg_db="${EITS_PG_DB:-eits_dev}"

  # Pending channel notifications: messages queued for this session via AgentWorker
  # (sender_role='user' = channel message routed to this agent) with status pending/sent,
  # arrived in the last hour, carrying a channel context.
  local sql
  sql="
SELECT
  COALESCE(s.name, 'session:' || m.session_id::text) AS from_name,
  c.name AS channel_name,
  c.id   AS channel_id,
  to_char(m.inserted_at AT TIME ZONE 'UTC', 'HH24:MI') AS ts,
  LEFT(REPLACE(REPLACE(m.body, E'\n', ' '), E'\r', ''), 120) AS snippet
FROM messages m
JOIN channels c ON c.id = m.channel_id
LEFT JOIN sessions s ON s.id = m.session_id
WHERE m.session_id = ${session_int}
  AND m.status IN ('pending', 'sent')
  AND m.channel_id IS NOT NULL
  AND m.inserted_at > NOW() - INTERVAL '1 hour'
  AND m.sender_role = 'user'
ORDER BY m.inserted_at ASC
LIMIT 10;
"

  local rows
  rows=$("$psql_bin" --no-psqlrc -U "$pg_user" -h "$pg_host" -d "$pg_db" \
    -t -A -F $'\x1f' -c "$sql" 2>/dev/null || true)

  [ -z "$rows" ] && return

  local output=""
  while IFS=$'\x1f' read -r from_name ch_name ch_id ts snippet; do
    [ -z "$ch_id" ] && continue
    output="${output}
- **${from_name}** in #${ch_name} [${ts}]: ${snippet}"
  done <<< "$rows"

  if [ -n "$output" ]; then
    echo ""
    echo "## Pending Notifications (buffered while idle — AgentWorker will deliver full prompts)"
    echo "$output"
    _log "injected pending notifications: $(echo "$rows" | wc -l | tr -d ' ') messages"
  fi
}

_inject_pending_notifications "${SESSION_INT_ID:-}"
