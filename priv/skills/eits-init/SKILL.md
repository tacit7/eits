---
name: eits-init
description: MUST be called at the start of every session to register with Eye in the Sky tracking system. Creates agent and session records for monitoring all work, tasks, commits, and notes throughout the session.
---

Initialize Eye in the Sky session tracking.

The startup/resume hooks inject these env vars automatically:
- `$EITS_SESSION_UUID` — session UUID
- `$EITS_PROJECT_ID` — project integer ID
- `$EITS_AGENT_UUID` — agent UUID (resume only; not set on new sessions)
- `$EITS_URL` — `http://localhost:5001/api/v1`

## Steps

1. **Check if already initialized** — resume hook sets `$EITS_AGENT_UUID` for existing sessions:
   ```bash
   echo "$EITS_AGENT_UUID"
   ```
   - Non-empty → already initialized. Report active and exit.
   - Empty → new session, proceed.

2. **Get session name and description**:
   - If `--name` and `--description` args were provided, use them.
   - If `$CLAUDE_CODE_REMOTE` is `"true"`, infer from the user's opening message.
   - Otherwise, ask the user. Both are required.
   - **Name**: short title for the session (e.g. "Fix login bug")
   - **Description**: one-line summary of the goal (e.g. "Session auth returns 401 on valid tokens")

3. **Get project name**: derive from git remote or directory name.

4. **Register the session**:
   ```bash
   eits sessions create \
     --session-id $EITS_SESSION_UUID \
     --name "<name>" \
     --description "<description>" \
     --project "<project_name>" \
     --model "claude-opus-4-6" \
     --entrypoint "${EITS_ENTRYPOINT:-}"

   # GET returns agent UUID (POST response agent_id is numeric, not the UUID)
   EITS_AGENT_UUID=$(eits sessions get $EITS_SESSION_UUID | jq -r '.agent_id')
   ```

   Both `--name` and `--description` are stored as separate fields on the session. Name is the display title; description provides context.

5. **Report success**: `"EITS active. Agent: $EITS_AGENT_UUID  Project: $EITS_PROJECT_ID"`

## Messaging Protocol

Check `$CLAUDE_CODE_ENTRYPOINT` to determine how to send DMs and commands:

```bash
echo "$CLAUDE_CODE_ENTRYPOINT"
```

| Entrypoint | Method | Reason |
|------------|--------|--------|
| `sdk-cli` | **EITS-CMD** | Spawned/headless agent — AgentWorker intercepts stdout, no HTTP needed |
| `cli` | **eits script** | Interactive session — no worker intercepting, use REST API |

**When `sdk-cli` (spawned agent) — output EITS-CMD lines in your text:**
```
EITS-CMD: dm --to <session_uuid> --message "your message"
EITS-CMD: task create <title>
EITS-CMD: task begin <title>
EITS-CMD: task update <id> <state_id>
EITS-CMD: task done <id>
EITS-CMD: task annotate <id> <body>
EITS-CMD: note <body>
EITS-CMD: note task <id> <body>
EITS-CMD: commit <hash>
```
The AgentWorker strips these from the visible stream and dispatches them in-process.

**When `sdk-cli` (interactive session) — use the eits script:**
```bash
eits dm --to <session_uuid> --message "your message"
eits tasks update <id> --state 4
eits tasks annotate <id> --body "..."
```

## EITS Workflow

**You MUST have a task `in_progress` before editing any files.**

```bash
# Two-command lifecycle (preferred)
eits tasks create --title "Task name" --description "Details"
eits tasks claim <task_id>
# claim: transitions → in-progress, self-assigns, links session, sets team status → working

# Finish
eits tasks complete <task_id> --message "What was done"
# complete: annotates, marks done, sets team status → done, DMs team lead
```

```bash
# Notes
eits notes create --parent-type session --parent-id $EITS_SESSION_UUID --body "..."

# Commits
eits commits create --hash <hash1> --hash <hash2>
# agent defaults from $EITS_AGENT_UUID
```

## Creating Workable Tasks (auto-worker)

```bash
eits tasks create --title "..." --description "..."
# → task_id; session linked automatically

psql -d eits_dev -c "INSERT INTO task_tags (task_id, tag_id) VALUES (<task_id>, 422);"
# tag_id 422 = sonnet, 421 = haiku
```

## eits CLI Reference

| Operation | Command |
|-----------|---------|
| Get session | `eits sessions get $EITS_SESSION_UUID` |
| Register session | `eits sessions create --session-id <uuid> --name <n> --description <d> --project <p> --model <m>` |
| Update session | `eits sessions update <uuid> [--status <s>] [--intent <text>] [--entrypoint <e>]` |
| End session | `eits sessions end $EITS_SESSION_UUID` |
| Get session context | `eits sessions context $EITS_SESSION_UUID` |
| Create task | `eits tasks create --title <t> --description <d> [--team <id>]` |
| Claim task (preferred) | `eits tasks claim <id>` |
| Complete task (preferred) | `eits tasks complete <id> --message <text>` |
| Start task (legacy) | `eits tasks start <id>` |
| Move to In Review (legacy) | `eits tasks update <id> --state 4` |
| Done task | `eits tasks done <id>` |
| Annotate task | `eits tasks annotate <id> --body <text>` |
| Add note | `eits notes create --parent-type session --parent-id $EITS_SESSION_UUID --body <text>` |
| Log commits | `eits commits create --hash <h1> [--hash <h2>]` |
| Link task (after-the-fact) | `eits tasks link-session <task_id>` |
