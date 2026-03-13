# EITS Hook Scripts

Claude Code integration scripts that manage session lifecycle and tool-use logging.

**Location:** `priv/scripts/eits-*.sh`

---

## Session Lifecycle

### eits-session-startup.sh

Runs when Claude Code session starts (SessionStart hook).

**Responsibilities:**
- Create session via REST API POST `/api/v1/sessions`
- Resolve project_name to project_id
- Set environment variables: `EITS_SESSION_ID`, `EITS_AGENT_ID`, `EITS_PROJECT_ID`
- Return session UUID to Claude Code

**Flow:**
1. Parse Claude Code context (session_id, description, project, model)
2. Call REST API with `session_id`, `project_name`, `description`, `model`, `provider`
3. Extract `uuid` and `agent_id` from response
4. Export env vars for hook scripts and spawned agents
5. Return UUID (stored in `.claude/eits/session_uuid`)

**Env vars set:**
```bash
EITS_SESSION_ID="<uuid>"
EITS_AGENT_ID=<integer_id>
EITS_PROJECT_ID=<integer> (or unset if project not found)
```

---

### eits-session-end.sh

Runs when Claude Code session ends (SessionEnd hook).

**Responsibilities:**
- Mark session as completed via REST API PATCH `/api/v1/sessions/:uuid`
- Clean up local temp files (session_uuid, etc.)
- Log session summary (commits, notes, tasks completed)

**Flow:**
1. Read `EITS_SESSION_ID` from `.claude/eits/session_uuid`
2. Call PATCH `/api/v1/sessions/{uuid}` with `status: "completed"`
3. Optionally call end-session workflow (upload session context, etc.)
4. Remove temp files

**Exit behavior:**
- Returns 0 (success) even if REST call fails (session may have already ended)
- Logs errors but doesn't block session exit

---

## Tool-Use Hooks

### eits-pre-tool-use.sh

Runs before Claude Code executes a tool (PreToolUse hook).

**Responsibilities:**
- Validate that an active task exists for the session
- Check that task is in "In Progress" state (state_id 2)
- Block tool execution if no active task

**Validation:**
```bash
# Query: SELECT * FROM tasks WHERE session_id = $EITS_SESSION_ID AND state_id = 2 LIMIT 1
psql -t -c "SELECT id FROM tasks WHERE session_id = $EITS_SESSION_ID AND state_id = 2 LIMIT 1"
```

**Exit codes:**
- `0` — Active task found; allow tool execution
- `1` — No active task; block execution (outputs helpful error message)

**Error message:**
```
No active EITS todo for session {project_id}. Workflow:
(1) i-todo create --title "Task"
(2) i-todo start --task_id <id>
(3) i-todo add-session --task_id <id> --session_id {uuid}
(4) do work
(5) i-todo status --task_id <id> --state_id 4 to move to In Review when done
```

---

### eits-post-tool-use.sh (Future)

Will run after tool execution to log tool use and results. Currently not implemented.

---

## Installation

```bash
./priv/scripts/install.sh
# Manually merge output into ~/.claude/settings.json
```

**Hooks registered:**
```json
{
  "hooks": {
    "SessionStart": "path/to/eits-session-startup.sh",
    "SessionEnd": "path/to/eits-session-end.sh",
    "PreToolUse": "path/to/eits-pre-tool-use.sh"
  }
}
```

---

## Helper Scripts

### sql/postgresql/check-active-todo.sh

Checks if an active task exists in PostgreSQL.

**Usage:**
```bash
./priv/scripts/sql/postgresql/check-active-todo.sh <session_uuid>
```

**Returns:**
- `0` and task ID — if task found
- `1` — if no active task

**Database query:**
```sql
SELECT id FROM tasks
WHERE session_id = (SELECT id FROM sessions WHERE uuid = $1)
  AND state_id = 2  -- In Progress
LIMIT 1
```

---

## Environment Variables

| Var | Set By | Purpose |
|-----|--------|---------|
| `EITS_SESSION_ID` | eits-session-startup.sh | Session UUID for API calls |
| `EITS_AGENT_ID` | eits-session-startup.sh | Integer agent ID for task ownership |
| `EITS_PROJECT_ID` | eits-session-startup.sh | Project ID (may be unset) |
| `EITS_API_KEY` | User (in .zshrc) | Bearer token for REST API |
| `EITS_URL` | User (optional) | REST API base URL (defaults to localhost:5001) |

---

## Troubleshooting

**"No active EITS todo" error:**
- Before running any tool, create a task: `i-todo create --title "..."`
- Start it: `i-todo start --task_id <id>`
- Link to session: `i-todo add-session --task_id <id> --session_id <uuid>`

**API connection failures:**
- Ensure EITS web server is running on port 5001
- Check `EITS_URL` env var (defaults to `http://localhost:5001`)
- Verify `EITS_API_KEY` is set in Claude Code environment

**Database errors:**
- PostgreSQL must be running and `eits_dev` database must exist
- Check `.claude/last_session_uuid` doesn't reference a deleted session
- Run `mix ecto.setup` to reset DB

---

## Future Enhancements

- PostToolUse hook to log tool use results and errors
- Automatic task creation for new sessions (instead of manual i-todo create)
- Session context auto-save on tool completion
