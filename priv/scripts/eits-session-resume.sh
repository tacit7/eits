#!/bin/bash
# EITS Session Hook — resume
# Resolves integer IDs from API and overwrites env vars in CLAUDE_ENV_FILE.

set -uo pipefail

EITS_DB="$HOME/.config/eye-in-the-sky/eits.db"
MAPPING_FILE="$HOME/.claude/hooks/session_agent_map.json"
EITS_BASE="${EITS_API_URL:-http://localhost:5001/api/v1}"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
MODEL=$(echo "$INPUT" | jq -r '.model // empty' 2>/dev/null || echo "")

echo "[EITS] resume: session=$SESSION_ID" >&2

[ -z "$SESSION_ID" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_DIR")

# Resolve integer IDs — API first, sqlite3 fallback
SESSION_INT_ID=""
AGENT_INT_ID=""
AGENT_ID=""

SESSION_INFO=$(curl -sf "$EITS_BASE/sessions/$SESSION_ID" 2>/dev/null || true)

if [ -n "$SESSION_INFO" ] && echo "$SESSION_INFO" | jq -e '.initialized == true' >/dev/null 2>&1; then
  SESSION_INT_ID=$(echo "$SESSION_INFO" | jq -r '.id // empty')
  AGENT_INT_ID=$(echo "$SESSION_INFO" | jq -r '.agent_int_id // empty')
  AGENT_ID=$(echo "$SESSION_INFO" | jq -r '.agent_id // empty')
  echo "[EITS] resume resolved via API: session=$SESSION_INT_ID agent=$AGENT_INT_ID" >&2
else
  SESSION_INT_ID=$(sqlite3 "$EITS_DB" "SELECT id FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1;" 2>/dev/null || true)
  EXISTING_AGENT=$(sqlite3 "$EITS_DB" "SELECT agent_id FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1;" 2>/dev/null || true)
  if [ -n "$EXISTING_AGENT" ]; then
    AGENT_INT_ID="$EXISTING_AGENT"
    AGENT_ID=$(sqlite3 "$EITS_DB" "SELECT uuid FROM agents WHERE id = $EXISTING_AGENT LIMIT 1;" 2>/dev/null || true)
  fi
  echo "[EITS] resume resolved via sqlite: session=$SESSION_INT_ID agent=$AGENT_INT_ID" >&2
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
  _set() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "$CLAUDE_ENV_FILE" 2>/dev/null; then
      sed -i '' "s|^${key}=.*|${key}=${val}|" "$CLAUDE_ENV_FILE"
    else
      echo "${key}=${val}" >> "$CLAUDE_ENV_FILE"
    fi
  }

  _set "EITS_SESSION_UUID" "$SESSION_ID"
  [ -n "${SESSION_INT_ID:-}" ] && _set "EITS_SESSION_ID" "$SESSION_INT_ID"
  [ -n "${AGENT_INT_ID:-}" ] && _set "EITS_AGENT_ID" "$AGENT_INT_ID"

  echo "[EITS] env vars updated: SESSION_UUID=$SESSION_ID SESSION_ID=${SESSION_INT_ID:-} AGENT_ID=${AGENT_INT_ID:-}" >&2
fi

# NATS (fire-and-forget)
DESCRIPTION=$(sqlite3 "$EITS_DB" "SELECT description FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1;" 2>/dev/null || true)
SESSION_NAME=$(sqlite3 "$EITS_DB" "SELECT name FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1;" 2>/dev/null || true)

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

**Session**: ${SESSION_NAME:-unnamed} (ID: ${SESSION_INT_ID:-$SESSION_ID})
**Agent ID**: ${AGENT_INT_ID:-$AGENT_ID}
**Project**: $PROJECT_NAME

Call \`/eits-init\` if this session needs a name, otherwise continue your work."

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
