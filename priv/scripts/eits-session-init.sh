#!/bin/bash
# EITS Session Initialization Hook (Go MCP Server)
# Fires on SessionStart (startup, resume)
# Injects context to prompt session initialization via MCP tools

set -uo pipefail

EITS_PG_DB="${EITS_PG_DB:-eits_dev}"
EITS_PG_USER="${EITS_PG_USER:-postgres}"
EITS_PG_HOST="${EITS_PG_HOST:-localhost}"
export PGPASSWORD="${EITS_PG_PASSWORD:-postgres}"
_pgq() { psql -U "$EITS_PG_USER" -h "$EITS_PG_HOST" -d "$EITS_PG_DB" -t -A -c "$1" 2>/dev/null; }

MAPPING_FILE="$HOME/.claude/hooks/session_agent_map.json"

# Parse input from Claude Code (read from stdin)
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || echo "")
SOURCE=$(echo "$INPUT" | jq -r '.source // "unknown"' 2>/dev/null || echo "unknown")
HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // "SessionStart"' 2>/dev/null || echo "SessionStart")
MODEL=$(echo "$INPUT" | jq -r '.model // empty' 2>/dev/null || echo "")

echo "[EITS] Hook triggered: $HOOK_EVENT ($SOURCE)" >&2

if [ -z "$SESSION_ID" ]; then
  echo "[EITS] No session_id provided, skipping" >&2
  exit 0
fi

# Determine project context
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_DIR")

# Escape for SQL
PROJECT_DIR_SQL="${PROJECT_DIR//\'/\'\'}"
PROJECT_NAME_SQL="${PROJECT_NAME//\'/\'\'}"

# Check if session already exists — try API first, fall back to psql
AGENT_ID=""
AGENT_INT_ID=""
SESSION_INT_ID=""
EITS_BASE="${EITS_API_URL:-http://localhost:5001/api/v1}"

SESSION_INFO=$(curl -sf "$EITS_BASE/sessions/$SESSION_ID" 2>/dev/null || true)

if [ -n "$SESSION_INFO" ] && echo "$SESSION_INFO" | jq -e '.initialized == true' >/dev/null 2>&1; then
  SESSION_INT_ID=$(echo "$SESSION_INFO" | jq -r '.id // empty')
  AGENT_INT_ID=$(echo "$SESSION_INFO" | jq -r '.agent_int_id // empty')
  AGENT_ID=$(echo "$SESSION_INFO" | jq -r '.agent_id // empty')
  echo "[EITS] Session resolved via API: session_int=$SESSION_INT_ID agent_int=$AGENT_INT_ID" >&2
else
  SESSION_INT_ID=$(_pgq "SELECT id FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1" || true)
  EXISTING_AGENT=$(_pgq "SELECT agent_id FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1" || true)
  if [ -n "$EXISTING_AGENT" ]; then
    AGENT_INT_ID="$EXISTING_AGENT"
    AGENT_ID=$(_pgq "SELECT uuid FROM agents WHERE id = $EXISTING_AGENT LIMIT 1" || true)
  fi
  echo "[EITS] Session resolved via psql: session_int=$SESSION_INT_ID agent_int=$AGENT_INT_ID" >&2
fi

if [ -n "$SESSION_INT_ID" ]; then
  echo "[EITS] Session already registered: $SESSION_ID -> agent=$AGENT_ID (int: $AGENT_INT_ID, session int: $SESSION_INT_ID)" >&2
  if [ -n "$AGENT_ID" ]; then
    if [ -f "$MAPPING_FILE" ]; then
      UPDATED=$(jq --arg sid "$SESSION_ID" --arg aid "$AGENT_ID" '.[$sid] = $aid' "$MAPPING_FILE" 2>/dev/null)
    else
      UPDATED=$(jq -n --arg sid "$SESSION_ID" --arg aid "$AGENT_ID" '{($sid): $aid}')
    fi
    echo "$UPDATED" > "$MAPPING_FILE"
  fi
else
  echo "[EITS] New session detected, will prompt MCP initialization" >&2
fi

_eits_set_var() {
  local key="$1" val="$2" file="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i '' "s|^${key}=.*|${key}=${val}|" "$file"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  grep -q "^EITS_API_URL=" "$CLAUDE_ENV_FILE" 2>/dev/null || echo "EITS_API_URL=http://localhost:5001/api/v1" >> "$CLAUDE_ENV_FILE"

  if [ "$SOURCE" = "resume" ]; then
    _eits_set_var "EITS_SESSION_ID" "${SESSION_INT_ID:-$SESSION_ID}" "$CLAUDE_ENV_FILE"
    if [ -n "${AGENT_INT_ID:-}" ]; then
      _eits_set_var "EITS_AGENT_ID" "$AGENT_INT_ID" "$CLAUDE_ENV_FILE"
    elif [ -n "$AGENT_ID" ]; then
      _eits_set_var "EITS_AGENT_ID" "$AGENT_ID" "$CLAUDE_ENV_FILE"
    fi
  else
    grep -q "^EITS_SESSION_ID=" "$CLAUDE_ENV_FILE" 2>/dev/null || echo "EITS_SESSION_ID=${SESSION_INT_ID:-$SESSION_ID}" >> "$CLAUDE_ENV_FILE"
    if ! grep -q "^EITS_AGENT_ID=" "$CLAUDE_ENV_FILE" 2>/dev/null; then
      if [ -n "${AGENT_INT_ID:-}" ]; then
        echo "EITS_AGENT_ID=$AGENT_INT_ID" >> "$CLAUDE_ENV_FILE"
      elif [ -n "$AGENT_ID" ]; then
        echo "EITS_AGENT_ID=$AGENT_ID" >> "$CLAUDE_ENV_FILE"
      fi
    fi
  fi

  # Resolve or create project by path
  PROJECT_ID=$(_pgq "SELECT id FROM projects WHERE path = '$PROJECT_DIR_SQL' LIMIT 1" || true)

  if [ -z "$PROJECT_ID" ]; then
    echo "[EITS] Creating new project: $PROJECT_NAME at $PROJECT_DIR" >&2
    PROJECT_ID=$(_pgq "
      INSERT INTO projects (name, path, active, inserted_at, updated_at)
      VALUES ('$PROJECT_NAME_SQL', '$PROJECT_DIR_SQL', true, NOW(), NOW())
      RETURNING id
    " || true)
  fi

  if [ -n "$PROJECT_ID" ]; then
    _pgq "
      UPDATE sessions SET project_id = $PROJECT_ID, git_worktree_path = '$PROJECT_DIR_SQL'
      WHERE uuid = '$SESSION_ID' AND project_id IS NULL
    " >/dev/null || true

    grep -q "^EITS_PROJECT_ID=" "$CLAUDE_ENV_FILE" 2>/dev/null || echo "EITS_PROJECT_ID=$PROJECT_ID" >> "$CLAUDE_ENV_FILE"
    echo "[EITS] Project ID: $PROJECT_ID" >&2
  fi

  echo "[EITS] Wrote env vars to CLAUDE_ENV_FILE" >&2
fi

# Publish session start to NATS (fire-and-forget)
if [ -n "$SESSION_ID" ]; then
  DESCRIPTION=$(_pgq "SELECT description FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1" || true)
  SESSION_NAME=$(_pgq "SELECT name FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1" || true)
  nats pub "events.session.start" "$(jq -nc \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "${AGENT_ID:-$SESSION_ID}" \
    --arg description "${DESCRIPTION:-}" \
    --arg name "${SESSION_NAME:-}" \
    --arg project_id "${PROJECT_ID:-}" \
    --arg project_name "$PROJECT_NAME" \
    --arg model "${MODEL:-}" \
    --arg provider "claude" \
    --arg worktree_path "$PROJECT_DIR" \
    '{session_id: $session_id, agent_id: $agent_id, description: $description, name: $name, project_name: $project_name, model: $model, provider: $provider, worktree_path: $worktree_path} | if $project_id != "" then . + {project_id: ($project_id | tonumber)} else . end')" 2>/dev/null &
  nats pub "events.session.update" "$(jq -nc \
    --arg session_id "$SESSION_ID" \
    --arg status "working" \
    '{session_id: $session_id, status: $status}')" 2>/dev/null &
fi

# Build context for Claude
if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && [ -z "$AGENT_ID" ]; then
  INIT_CONTEXT="# Eye in the Sky Integration Active (Headless Mode)

**IMPORTANT**: You are running in headless/automated mode. Auto-initialize this session:

1. **Auto-Initialize**: Call \`i-start-session\` immediately with:
   - \`description\`: Brief summary of your task/instructions (1-2 sentences)
   - Derive session name from your first task
2. **Track Tasks**: Use i-todo tools to create and manage tasks
3. **Log Commits**: Commits are auto-tracked via git hooks
4. **Save Context**: Use i-save-session-context for important findings

Current session context:"
else
  INIT_CONTEXT="# Eye in the Sky Integration Active

**IMPORTANT**: Call \`/eits-init\` to name and describe your session.

Quick reference:
1. **Initialize Session**: \`/eits-init\` - Provide name and description for this work
2. **Track Tasks**: Use i-todo tools to create and manage tasks
3. **Log Commits**: Commits are auto-tracked via git hooks
4. **Save Context**: Use i-save-session-context for important findings

Environment (available in Bash tool):
- \`echo \$EITS_SESSION_ID\` - Current session ID (integer)
- \`echo \$EITS_AGENT_ID\`   - Current agent ID (integer)
- \`echo \$EITS_PROJECT_ID\` - Current project ID (integer)

Current session context:"
fi

if [ -f "$PROJECT_DIR/mix.exs" ]; then
  INIT_CONTEXT="$INIT_CONTEXT

**Project Type**: Elixir/Phoenix
**Project**: $PROJECT_NAME
**Path**: $PROJECT_DIR"
elif [ -f "$PROJECT_DIR/package.json" ]; then
  INIT_CONTEXT="$INIT_CONTEXT

**Project Type**: Node.js
**Project**: $PROJECT_NAME
**Path**: $PROJECT_DIR"
elif [ -f "$PROJECT_DIR/go.mod" ]; then
  INIT_CONTEXT="$INIT_CONTEXT

**Project Type**: Go Module
**Project**: $PROJECT_NAME
**Path**: $PROJECT_DIR"
elif [ -f "$PROJECT_DIR/.git/config" ]; then
  INIT_CONTEXT="$INIT_CONTEXT

**Project Type**: Git Repository
**Project**: $PROJECT_NAME
**Path**: $PROJECT_DIR"
else
  INIT_CONTEXT="$INIT_CONTEXT

**Project**: $PROJECT_NAME
**Path**: $PROJECT_DIR"
fi

if [ -n "$AGENT_ID" ]; then
  INIT_CONTEXT="$INIT_CONTEXT

**Agent ID**: ${AGENT_INT_ID:-$AGENT_ID}
**Session ID**: ${SESSION_INT_ID:-$SESSION_ID}"
fi

cat <<EOF
{
  "continue": true,
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $(printf '%s\n' "$INIT_CONTEXT" | jq -Rs .)
  }
}
EOF

exit 0
