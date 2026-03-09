#!/bin/bash
# EITS Session Hook — startup / clear / compact
# Writes env vars to CLAUDE_ENV_FILE and injects /eits-init prompt.

set -uo pipefail

EITS_DB="$HOME/.config/eye-in-the-sky/eits.db"
EITS_BASE="${EITS_API_URL:-http://localhost:5001/api/v1}"

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
MODEL=$(echo "$INPUT" | jq -r '.model // empty' 2>/dev/null || echo "")

echo "[EITS] startup: session=$SESSION_ID" >&2

[ -z "$SESSION_ID" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_DIR")
PROJECT_DIR_SQL="${PROJECT_DIR//\'/\'\'}"
PROJECT_NAME_SQL="${PROJECT_NAME//\'/\'\'}"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "EITS_API_URL=http://localhost:5001/api/v1" >> "$CLAUDE_ENV_FILE"
  echo "EITS_SESSION_UUID=$SESSION_ID" >> "$CLAUDE_ENV_FILE"

  # Resolve or create project
  PROJECT_ID=$(sqlite3 "$EITS_DB" "SELECT id FROM projects WHERE path = '$PROJECT_DIR_SQL' LIMIT 1;" 2>/dev/null || true)
  if [ -z "$PROJECT_ID" ]; then
    sqlite3 "$EITS_DB" "
      INSERT INTO projects (name, path, active, inserted_at, updated_at)
      VALUES ('$PROJECT_NAME_SQL', '$PROJECT_DIR_SQL', 1, datetime('now'), datetime('now'));
    " 2>/dev/null || true
    PROJECT_ID=$(sqlite3 "$EITS_DB" "SELECT last_insert_rowid();" 2>/dev/null || true)
  fi
  [ -n "$PROJECT_ID" ] && echo "EITS_PROJECT_ID=$PROJECT_ID" >> "$CLAUDE_ENV_FILE"
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

CONTEXT="# Eye in the Sky Integration Active

**IMPORTANT**: Call \`/eits-init\` to name and describe your session.

1. **Initialize Session**: \`/eits-init\` - Provide name and description for this work
2. **Track Tasks**: Use i-todo tools to create and manage tasks
3. **Log Commits**: Commits are auto-tracked via git hooks
4. **Save Context**: Use i-save-session-context for important findings

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
