---
name: eits-cli
description: Use when an agent needs the correct eits CLI command syntax, flags, dispatch mode, environment setup, or subcommand behavior. Triggers on: "how do I use eits", "what's the eits command for", "eits CLI reference", sessions/tasks/notes/commits/agents/jobs/timer/channels/teams/prompts/notifications flags, dispatch mode confusion (cli vs sdk-cli), EITS_URL setup, or any eits subcommand question.
user-invocable: true
context: fork
allowed-tools: Bash
---

# EITS CLI

The `eits` bash script is the sole interface to the EITS REST API at `http://localhost:5001/api/v1`. All agents use it directly. EITS-CMD directives are **deprecated**.

## Live Session Context

!eits tasks active --json 2>/dev/null | jq -r 'if ((.tasks // []) | length) > 0 then "Active tasks: " + ((.tasks // []) | map("\(.id): \(.title)") | join("; ")) else "No active tasks" end' 2>/dev/null || echo "(active tasks unavailable)"

!echo "Session: ${EITS_SESSION_UUID:-(not set)} | Project: ${EITS_PROJECT_ID:-(not set)} | URL: ${EITS_URL:-http://localhost:5001/api/v1}"

---

## Dispatch Modes

EITS agents run in one of two dispatch modes:

- **`cli`** — interactive agent running in the current terminal/session
- **`sdk-cli`** — spawned or delegated agent running through the SDK CLI wrapper

Both modes use the **same `eits` command syntax**. Do not change task, note, commit, or session commands based on dispatch mode. Dispatch mode only matters when a command explicitly accepts a dispatch-related flag (e.g. agent spawn, job queue). For those flags, see `commands.md`.

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
# Can also be done inline with complete:
eits tasks complete <task_id> --message "..." --commit <sha>
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

If `EITS_SESSION_UUID` is not set, task commands will not link work to a session. If `EITS_PROJECT_ID` is not set and a command requires it, pass `--project-id <id>` explicitly or see `commands.md` for project commands.

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
