#!/bin/bash
# EITS Session Initialization Hook (Go MCP Server)
# Fires on SessionStart (startup, resume)
# Injects context to prompt session initialization via MCP tools

set -uo pipefail

EITS_DB="$HOME/.config/eye-in-the-sky/eits.db"
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

# Sanitize for SQLite string interpolation: escape single quotes as ''
PROJECT_DIR_SQL="${PROJECT_DIR//\'/\'\'}"
PROJECT_NAME_SQL="${PROJECT_NAME//\'/\'\'}"

# Check if session already exists in database
AGENT_ID=""
EXISTING_SESSION=$(sqlite3 "$EITS_DB" "SELECT agent_id FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1;" 2>/dev/null || true)
SESSION_INT_ID=$(sqlite3 "$EITS_DB" "SELECT id FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1;" 2>/dev/null || true)

if [ -n "$EXISTING_SESSION" ]; then
  # Session exists, get agent_id UUID for NATS/mapping; integer is EXISTING_SESSION
  AGENT_ID=$(sqlite3 "$EITS_DB" "SELECT uuid FROM agents WHERE id = $EXISTING_SESSION LIMIT 1;" 2>/dev/null || true)
  AGENT_INT_ID="$EXISTING_SESSION"
  echo "[EITS] Session already registered: $SESSION_ID -> $AGENT_ID (int: $AGENT_INT_ID, session int: $SESSION_INT_ID)" >&2

  # Update mapping file
  if [ -n "$AGENT_ID" ]; then
    if [ -f "$MAPPING_FILE" ]; then
      UPDATED=$(jq --arg sid "$SESSION_ID" --arg aid "$AGENT_ID" '.[$sid] = $aid' "$MAPPING_FILE" 2>/dev/null)
    else
      UPDATED=$(jq -n --arg sid "$SESSION_ID" --arg aid "$AGENT_ID" '{($sid): $aid}')
    fi
    echo "$UPDATED" > "$MAPPING_FILE"
  fi
else
  # Check mapping file for cached agent_id
  if [ -f "$MAPPING_FILE" ]; then
    AGENT_ID=$(jq -r ".\"$SESSION_ID\" // empty" "$MAPPING_FILE" 2>/dev/null || echo "")
  fi

  if [ -z "$AGENT_ID" ]; then
    AGENT_INT_ID=""
    echo "[EITS] New session detected, will prompt MCP initialization" >&2
  fi
fi

# Write env vars via CLAUDE_ENV_FILE so MCP server picks them up
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "EITS_SESSION_ID=${SESSION_INT_ID:-$SESSION_ID}" >> "$CLAUDE_ENV_FILE"

  if [ -n "${AGENT_INT_ID:-}" ]; then
    echo "EITS_AGENT_ID=$AGENT_INT_ID" >> "$CLAUDE_ENV_FILE"
  elif [ -n "$AGENT_ID" ]; then
    echo "EITS_AGENT_ID=$AGENT_ID" >> "$CLAUDE_ENV_FILE"
  fi

  # Resolve or create project by path
  PROJECT_ID=$(sqlite3 "$EITS_DB" "SELECT id FROM projects WHERE path = '$PROJECT_DIR_SQL' LIMIT 1;" 2>/dev/null || true)

  if [ -z "$PROJECT_ID" ]; then
    # Project doesn't exist, create it
    echo "[EITS] Creating new project: $PROJECT_NAME at $PROJECT_DIR" >&2
    sqlite3 "$EITS_DB" "
      INSERT INTO projects (name, path, active, inserted_at, updated_at)
      VALUES ('$PROJECT_NAME_SQL', '$PROJECT_DIR_SQL', 1, datetime('now'), datetime('now'));
    " 2>/dev/null || true
    PROJECT_ID=$(sqlite3 "$EITS_DB" "SELECT last_insert_rowid();" 2>/dev/null || true)
  fi

  if [ -n "$PROJECT_ID" ] && [ "$PROJECT_ID" != "" ]; then
    # Update session with project_id if it's NULL
    if [ -n "$EXISTING_SESSION" ]; then
      sqlite3 "$EITS_DB" "
        UPDATE sessions SET project_id = $PROJECT_ID, git_worktree_path = '$PROJECT_DIR_SQL'
        WHERE uuid = '$SESSION_ID' AND project_id IS NULL;
      " 2>/dev/null || true
    fi

    echo "EITS_PROJECT_ID=$PROJECT_ID" >> "$CLAUDE_ENV_FILE"
    echo "[EITS] Project ID: $PROJECT_ID" >&2
  fi

  echo "[EITS] Wrote env vars to CLAUDE_ENV_FILE" >&2
fi

# Publish session start to NATS (fire-and-forget)
if [ -n "$SESSION_ID" ]; then
  DESCRIPTION=$(sqlite3 "$EITS_DB" "SELECT description FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1;" 2>/dev/null || true)
  SESSION_NAME=$(sqlite3 "$EITS_DB" "SELECT name FROM sessions WHERE uuid = '$SESSION_ID' LIMIT 1;" 2>/dev/null || true)
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
  # Headless mode: auto-initialize session
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
  # Interactive mode: prompt for /eits-init
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

# Add project info
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

# Add agent_id to context if we have it
if [ -n "$AGENT_ID" ]; then
  INIT_CONTEXT="$INIT_CONTEXT

**Agent ID**: ${AGENT_INT_ID:-$AGENT_ID}
**Session ID**: ${SESSION_INT_ID:-$SESSION_ID}"
fi

# Output JSON response with context injection
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
