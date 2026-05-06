---
name: eits-cli
description: Use when an agent needs the correct eits CLI command syntax, flags, dispatch mode, environment setup, or subcommand behavior. Triggers on: "how do I use eits", "what's the eits command for", "eits CLI reference", sessions/tasks/notes/commits/agents/jobs/timer/channels/teams/prompts/notifications flags, dispatch mode confusion (cli vs sdk-cli), EITS_URL setup, or any eits subcommand question.
user-invocable: true
context: fork
allowed-tools: Bash
---

# EITS CLI

The `eits` bash script is the sole interface to the EITS REST API. By default it targets `http://localhost:5001/api/v1`, unless `EITS_URL` overrides it.

All agents — including interactive `cli` agents and spawned `sdk-cli` agents — use the same `eits` script directly. Do not use deprecated EITS-CMD directives.

## Live Session Context

!eits tasks active --json 2>/dev/null | jq -r 'if ((.tasks // []) | length) > 0 then "Active tasks: " + ((.tasks // []) | map("\(.id): \(.title)") | join("; ")) else "No active tasks" end' 2>/dev/null || echo "(active tasks unavailable)"

!echo "Agent: ${EITS_AGENT_UUID:-(not set)} | Session: ${EITS_SESSION_UUID:-(not set)} | Project: ${EITS_PROJECT_ID:-(not set)} | URL: ${EITS_URL:-http://localhost:5001/api/v1}"

---

## Dispatch Modes

EITS agents run in one of two dispatch modes:

- **`cli`** — interactive agent running in the current terminal/session
- **`sdk-cli`** — spawned or delegated agent running through the SDK CLI wrapper

Both modes use the **same `eits` command syntax**. Do not change task, note, commit, or session commands based on dispatch mode. Dispatch mode only matters for commands such as `eits agents spawn` or `eits jobs create` that explicitly accept a dispatch-related flag. For those flags, see `commands.md`.

---

## Quick Start: Task Lifecycle

```bash
# 1. Start work — creates task, links to session, sets In Progress atomically
eits tasks begin --title "What you're doing" [--description "..."] [--priority <p>] [--tag <id|name>]
# --tag is repeatable: --tag bug --tag auth

# 2. OR claim/start an existing task (orchestrator-assigned)
eits tasks begin --id <task_id>

# tasks begin has two modes:
#   without --id: creates a NEW task and marks it In Progress
#   with --id:    claims an EXISTING task and marks it In Progress

# 3. Annotate after the fact
eits tasks annotate <task_id> --body "What changed, what was learned, what remains"

# 4. Finish (atomic: annotates + marks Done in one round-trip)
eits tasks complete <task_id> --message "What was done and why"

# 5. Log commits — auto-links to current session via $EITS_AGENT_UUID/$EITS_SESSION_UUID
eits commits create --hash <sha>
# Can also be done inline with complete (--commit is repeatable for multiple hashes):
eits tasks complete <task_id> --message "..." --commit <sha1> --commit <sha2>
```

---

## Required Task Rule

**You MUST have a task In Progress before editing files.** The write hook blocks edits if no task is active.

If blocked:

```bash
# Check what's active
eits tasks active

# Start a new task
eits tasks begin --title "Describe the work"

# Or claim an existing task
eits tasks begin --id <task_id>
```

---

## Task Scoping

`eits tasks list` scopes to the current session when `EITS_SESSION_UUID` is set. Pass `--all` to see across sessions.

If `EITS_SESSION_UUID` is not set, `tasks begin`, `tasks annotate`, `tasks complete`, and `commits create` may not attach work to the intended session. Do not assume session linkage unless `EITS_SESSION_UUID` is present.

If `EITS_PROJECT_ID` is not set and a command requires a project, read `commands.md` for the command-specific project flag — the flag name varies by subcommand.

---

## Tag Discovery

```bash
eits tags list [--q <query>]   # find tag IDs and names
```

`--tag` on task commands accepts either the numeric ID or the name directly.

---

## State Reference

`--state` accepts positional numbers (1-4) or aliases. These are **not** raw DB IDs.

| Pos | Name        | Aliases                              |
|-----|-------------|--------------------------------------|
| 1   | To Do       | `todo`, `to-do`, `to do`             |
| 2   | In Progress | `start`, `in-progress`, `progress`   |
| 3   | In Review   | `review`, `in-review`                |
| 4   | Done        | `done`, `complete`, `completed`      |

Run `eits tasks states` for the authoritative list.

---

## When More Detail Is Needed

Read `commands.md` before answering questions about:
- sessions, agents, teams, dm, notes, channels, jobs, timer, prompts, projects, notifications
- any flag not shown in this file

Read `gotchas.md` before answering questions about:
- environment variables or `EITS_URL` setup
- session/project scoping behavior
- blocked writes or hook behavior
- surprising JSON output shapes
- deprecated EITS-CMD behavior
