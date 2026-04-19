---
name: task-workable
description: Create a new task and tag it as workable for the auto-worker jobs. Takes model (haiku or sonnet) and description as arguments.
user-invocable: true
---

# task-workable

Create a new EITS task and tag it for the workable auto-worker.

## Usage

```
/task-workable <model> <description>
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

Use `i-speak` to announce the result.
