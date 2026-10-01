---
name: eits-task-workable
description: Create a new task and tag it as workable for the auto-worker jobs. Takes model (haiku or sonnet) and description as arguments.
user-invocable: true
---

# EITS Task Workable

## Codex Runtime Notes

- Codex agents use the `eits` CLI directly. Do not emit `EITS-CMD:` directives and do not gate CLI usage on `CLAUDE_CODE_ENTRYPOINT`.
- Codex startup hooks may persist non-secret identity vars to `~/.eits/codex/sessions/<session_id>.env`. Plain `eits` calls auto-load that file only when `EITS_CODEX_SESSION_ID`, `CODEX_THREAD_ID`, or `CODEX_SESSION_ID` is set.
- For shell commands that expand `$EITS_SESSION_UUID`, `$EITS_SESSION_ID`, `$EITS_AGENT_UUID`, `$EITS_AGENT_ID`, or `$EITS_PROJECT_ID`, source the session env in the same command when needed:

```bash
. ~/.eits/codex/sessions/<session_id>.env 2>/dev/null || true
```

- Use `$EITS_SESSION_UUID` for UUID-only commands and `$EITS_SESSION_ID` for integer session contexts. If no Codex session id or EITS env is known, ask the user before running identity-scoped commands.

Create a new EITS task and tag it for the workable auto-worker.
For Codex sessions, source `~/.eits/codex/sessions/<session_id>.env` in the
same Bash command before using `$EITS_PROJECT_ID` shell expansion. Plain `eits`
CLI calls auto-load the session-specific file only when `EITS_CODEX_SESSION_ID`,
`CODEX_THREAD_ID`, or `CODEX_SESSION_ID` is set. If no session id is known, ask
the user for it.

## Usage

```
/eits-task-workable <model> <description>
```

- `model` — `haiku` or `sonnet`
- `description` — what the task should do

## Rules

- Tasks must be in **To Do state (state_id: 1)** — the auto-worker picks up tasks by tag + To Do state
- **Never call `eits tasks start`** on workable tasks
- **No session or agent ownership** — pass `--session ""` and `--agent ""` to suppress the CLI defaults
- The project defaults from `$EITS_PROJECT_ID` — do NOT hardcode a project ID

## Steps

1. Parse `model` and `description` from the args. If args are missing, ask the user for them.

2. Determine the tag:
   - `haiku` → tag_id: 421 (workable)
   - `sonnet` → tag_id: 422 (workable-sonnet)
   - Any other model → tell the user only `haiku` and `sonnet` are supported.

3. Create the task. Pass `--session ""` and `--agent ""` to prevent auto-linking to the current session:
```bash
eits tasks create \
  --title "<description>" \
  --description "<description>" \
  --session "" \
  --agent ""
```

`project_id` defaults from `$EITS_PROJECT_ID` and is sent as a number automatically.

4. Extract `task_id` from the response JSON (`.task_id` field).

5. Assign the tag:
```bash
eits tasks tag <task_id> <tag_id>
```

6. Confirm to the user:
   - Task ID
   - Title
   - Which model will pick it up
   - That it will be picked up within 10 minutes

Report the result in the final response.
