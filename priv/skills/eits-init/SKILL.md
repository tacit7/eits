---
name: eits-init
description: Fallback session registration for EITS. Only needed when auto-registration in the startup hook failed (EITS server was down at session start). Check $EITS_AGENT_UUID first — if set, exit immediately.
---

Initialize Eye in the Sky session tracking.

The startup hook now auto-registers all sessions. This skill is only needed when that failed.

The startup/resume hooks inject these env vars automatically:
- `$EITS_SESSION_UUID` — session UUID
- `$EITS_PROJECT_ID` — project integer ID
- `$EITS_AGENT_UUID` — agent UUID (set by startup hook for all sessions)
- `$EITS_URL` — `http://localhost:5001/api/v1`

## Steps

1. **Check if already registered** — startup hook sets `$EITS_AGENT_UUID` for all sessions:
   ```bash
   echo "$EITS_AGENT_UUID"
   ```
   - Non-empty → already registered. Report active and exit immediately.
   - Empty → auto-registration failed, proceed.

2. **Register the session**:
   ```bash
   eits sessions create \
     --session-id $EITS_SESSION_UUID \
     --project "$(basename $(pwd))" \
     --model "claude-opus-4-6" \
     --entrypoint "${EITS_ENTRYPOINT:-}"

   export EITS_AGENT_UUID=$(eits sessions get $EITS_SESSION_UUID | jq -r '.agent_uuid')
   ```

3. **Report success**: `"EITS active. Agent: $EITS_AGENT_UUID  Project: $EITS_PROJECT_ID"`

## Messaging Protocol

All agents use the `eits` CLI script for DMs and commands:

```bash
eits dm --to <session_uuid_or_integer_id> --message "your message"
eits tasks begin --title "<title>"
eits tasks complete <id> --message "..."
# If complete fails, fall back to:
#   eits tasks annotate <id> --body "..."
#   eits tasks update <id> --state done
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
