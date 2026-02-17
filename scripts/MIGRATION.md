# Hook Migration from TypeScript to Go

## What Changed

All EITS Claude Code hooks have been migrated from the TypeScript CLI to work with the Go MCP server using direct SQLite access.

## Key Changes

### Before (TypeScript)
```bash
EITS_BIN="$HOME/projects/eits/core-ts/build/index.js"
"$EITS_BIN" i-update-status --agent-id "$agent_id" --status "working"
```

### After (Go/SQLite)
```bash
EITS_DB="$HOME/.config/eye-in-the-sky/eits.db"
sqlite3 "$EITS_DB" "UPDATE sessions SET status = 'working' WHERE uuid = '$session_id';"
```

## Updated Hooks

### 1. eits-session-init.sh
- **Before**: Called TypeScript CLI `i-start-session` to create session
- **After**: Checks SQLite for existing session, injects context for MCP initialization
- **Change**: Simplified to use database lookups instead of CLI calls

### 2. eits-agent-working.sh
- **Before**: Called TypeScript CLI `i-update-status`
- **After**: Direct SQLite UPDATE on `sessions` table
- **Change**: Status now tracked on sessions, not agents

### 3. eits-session-end.sh
- **Before**: Called TypeScript CLI to set agent status
- **After**: Direct SQLite UPDATE to mark session completed
- **Change**: Status tracked on sessions table

### 4. eits-session-compact.sh
- **Before**: Called TypeScript CLI `i-end` with status "compacted"
- **After**: Direct SQLite UPDATE to mark session as compacted
- **Change**: Simplified database access

### 5. eits-session-stop.sh ✨ NEW
- **Purpose**: Handle Ctrl+C interrupts
- **Action**: Sets session status to "waiting" instead of "completed"
- **Database**: `UPDATE sessions SET status = 'waiting', ended_at = CURRENT_TIMESTAMP`

### 6. eits-pre-tool-use.sh ✨ NEW
- **Purpose**: Track tool calls before execution
- **Action**: Logs to `actions` table with `action_type = 'tool_use'`
- **Data**: Tool name, sanitized params (500 char max)

### 7. eits-post-tool-use.sh ✨ NEW
- **Purpose**: Track tool results after execution
- **Action**: Logs to `actions` table as `tool_success` or `tool_error`
- **Data**: Tool name, result summary (200 char max)

## Schema Changes

### Sessions Table (v2)
```sql
-- Status now tracked on sessions, not agents
sessions.status: 'active' | 'working' | 'waiting' | 'completed' | 'compacted'
sessions.ended_at: TIMESTAMP
sessions.last_activity_at: TIMESTAMP
```

### Actions Table
```sql
-- New action types for tool tracking
actions.action_type: 'tool_use' | 'tool_success' | 'tool_error' | ...
actions.description: Tool name and status
actions.details: JSON params or result summary
```

## Installation

Run the install script to deploy updated hooks:

```bash
cd /Users/urielmaldonado/projects/eits/core
./scripts/hooks/install.sh
```

This will:
1. Copy all hooks to `~/.claude/hooks/`
2. Make them executable
3. Provide settings.json merge instructions

## Verification

After installation, verify hooks are working:

```bash
# Check hook files
ls -lah ~/.claude/hooks/eits-*.sh

# Check settings configuration
jq '.hooks' ~/.claude/settings.json

# Start a new Claude Code session and verify:
# 1. SessionStart hook fires (check logs)
# 2. Session created in database
# 3. Status set to "working"
# 4. Tool usage logged in actions table
```

## Troubleshooting

### Hooks not firing
- Check `~/.claude/settings.json` has correct paths
- Verify hooks are executable: `chmod +x ~/.claude/hooks/eits-*.sh`
- Check stderr output: hooks log to stderr

### Database errors
- Verify database exists: `ls -lah ~/.config/eye-in-the-sky/eits.db`
- Check schema version: `sqlite3 ~/.config/eye-in-the-sky/eits.db "SELECT * FROM schema_migrations;"`

### Missing session data
- SessionStart hook should run before any MCP calls
- Check mapping file: `cat ~/.claude/hooks/session_agent_map.json`
- Verify env vars: `echo $EITS_SESSION_ID $EITS_AGENT_ID`

## Migration Checklist

- [x] Remove TypeScript binary references
- [x] Update to use SQLite directly
- [x] Migrate agent status to session status
- [x] Add Stop hook for interrupt handling
- [x] Add PreToolUse hook for tool tracking
- [x] Add PostToolUse hook for result tracking
- [x] Create install script
- [x] Generate settings.json template
- [x] Update documentation
- [x] Deploy to ~/.claude/hooks/

## Next Steps

1. Test hooks in a new Claude Code session
2. Verify tool tracking in actions table
3. Monitor logs for any errors
4. Consider adding UserPromptSubmit hook for user input tracking
