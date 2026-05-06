---
name: eits-cli
description: Use when an agent needs the correct eits CLI command syntax, flags, or dispatch mode. Triggers on: "how do I use eits", "what's the eits command for", "eits CLI reference", sessions/tasks/notes/commits/agents/jobs/timer/channels/teams/prompts/notifications flags, dispatch mode confusion (cli vs sdk-cli), EITS_URL setup, or any eits subcommand question.
user-invocable: true
context: fork
allowed-tools: Bash
---

# EITS CLI

The `eits` bash script is the sole interface to the EITS REST API at `http://localhost:5001/api/v1`. All agents — interactive (`cli`) and spawned (`sdk-cli`) — use it directly. EITS-CMD directives are **deprecated**.

## Live Session Context

!eits tasks active --json 2>/dev/null | jq -r 'if .tasks then "Active tasks: \(.tasks | length) — \([.tasks[].title] | join(", "))" else "No active tasks" end' 2>/dev/null || echo "(active tasks unavailable)"

!echo "Session: ${EITS_SESSION_UUID:-(not set)} | Project: ${EITS_PROJECT_ID:-(not set)} | URL: ${EITS_URL:-http://localhost:5001/api/v1}"

---

## Quick Start — Task Lifecycle

This is what you'll use 90% of the time:

```bash
# 1. Start work (creates + links to session + sets In Progress atomically)
eits tasks begin --title "What you're doing"

# 2. Do your work...

# 3. Finish (annotates + marks Done in one round-trip)
eits tasks complete <task_id> --message "What was done and why"

# 4. Log commits
eits commits create --hash <sha>
```

**Rules:**
- You MUST have a task In Progress before editing files. The write hook blocks if you don't.
- `begin` always creates a new task. To claim an existing one: `eits tasks begin --id <task_id>`.
- `tasks list` scopes to your session when `EITS_SESSION_UUID` is set. Pass `--all` to see everything.

---

## State Reference

`--state` accepts positional numbers (1–4) or name aliases. These are **not** the raw DB IDs.

| Pos | Name        | Aliases                              |
|-----|-------------|--------------------------------------|
| 1   | To Do       | `todo`, `to-do`, `to do`             |
| 2   | In Progress | `start`, `in-progress`, `progress`   |
| 3   | In Review   | `review`, `in-review`                |
| 4   | Done        | `done`, `complete`, `completed`      |

Run `eits tasks states` for the authoritative list.

---

## Full Command Reference

See [commands.md](commands.md) for the complete surface: sessions, agents, teams, dm, notes, channels, jobs, timer, prompts, projects, notifications.

## Known Gotchas & Environment Variables

See [gotchas.md](gotchas.md).
