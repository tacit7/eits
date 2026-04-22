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

   EITS_AGENT_UUID=$(eits sessions get $EITS_SESSION_UUID | jq -r '.agent_id')
   ```

   Both `--name` and `--description` are stored as separate fields on the session. Name is the display title; description provides context.

5. **Report success**: `"EITS active. Agent: $EITS_AGENT_UUID  Project: $EITS_PROJECT_ID"`

## Messaging Protocol

All agents use the `eits` CLI script for DMs and commands:

```bash
eits dm --to <session_uuid_or_integer_id> --message "your message"
eits tasks begin --title "<title>"
eits tasks annotate <id> --body "..."
eits tasks update <id> --state 3
eits commits create --hash <hash>
```

## EITS Workflow

**You MUST have a task `in_progress` before editing any files.**

```bash
# Canonical lifecycle (1-command start)
eits tasks begin --title "Task name"
# begin: creates + transitions → in-progress + links session atomically

# Finish (atomic server-side transaction: annotate + mark done)
eits tasks complete <task_id> --message "What was done"
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
eits tasks create --title "..." --description "..." --session "" --agent ""
# pass --session "" --agent "" to avoid linking to current session

eits tasks tag <task_id> 422   # 422 = sonnet, 421 = haiku
```

## eits CLI Reference

| Operation | Command |
|-----------|---------|
| Get session | `eits sessions get $EITS_SESSION_UUID` |
| Register session | `eits sessions create --session-id <uuid> --name <n> --description <d> --project <p> --model <m>` |
| Update session | `eits sessions update <uuid> [--status <s>] [--intent <text>] [--entrypoint <e>]` |
| End session | `eits sessions end $EITS_SESSION_UUID` |
| Get session context | `eits sessions context $EITS_SESSION_UUID` |
| Create + start task | `eits tasks begin --title <t>` |
| Complete task | `eits tasks complete <id> --message <text>` |
| Update state by alias | `eits tasks update <id> --state done` (also: `start`, `in-review`, `review`, `todo`) |
| Update state by ID | `eits tasks update <id> --state 3` |
| Annotate task | `eits tasks annotate <id> --body <text>` |
| Add note | `eits notes create --parent-type session --parent-id $EITS_SESSION_UUID --body <text>` |
| Log commits | `eits commits create --hash <h1> [--hash <h2>]` |
| Link task (after-the-fact) | `eits tasks link-session <task_id>` |
