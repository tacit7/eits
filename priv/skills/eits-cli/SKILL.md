---
name: eits-cli
description: Use when an agent needs the correct eits CLI command syntax, flags, dispatch mode, environment setup, or subcommand behavior. Triggers on: "how do I use eits", "what's the eits command for", "eits CLI reference", sessions/tasks/notes/commits/agents/jobs/timer/channels/teams/prompts/notifications flags, dispatch mode confusion (cli vs sdk-cli), EITS_URL setup, or any eits subcommand question.
user-invocable: true
context: fork
allowed-tools: Bash
---

# EITS CLI

This skill has three files:
- **`SKILL.md`** — quick rules, safe defaults, and operating contract (this file)
- **`commands.md`** — full command syntax and flags for every subcommand
- **`gotchas.md`** — environment issues, known bugs, and failure modes

The `eits` bash script is the sole interface to the EITS REST API. It defaults to `http://localhost:5001/api/v1`; override with `EITS_URL`. All agents — interactive (`cli`) and spawned (`sdk-cli`) — use the same `eits` script. Do not use deprecated EITS-CMD directives.

## Live Session Context

!eits tasks active --json 2>/dev/null | jq -r 'if ((.tasks // []) | length) > 0 then "Active tasks: " + ((.tasks // []) | map("\(.id): \(.title)") | join("; ")) else "No active tasks" end' 2>/dev/null || echo "(active tasks unavailable)"

!echo "Agent: ${EITS_AGENT_UUID:-(not set)} | Session: ${EITS_SESSION_UUID:-(not set)} | Project: ${EITS_PROJECT_ID:-(not set)} | URL: ${EITS_URL:-http://localhost:5001/api/v1}"

---

## Agent Operating Rules

- **Do not guess** command syntax, flags, argument order, or JSON output shapes.
- Read `commands.md` before using any command or flag not shown in this file.
- Read `gotchas.md` before handling environment setup, hooks, session/project scoping, JSON parsing, DMs, spawning, or known bugs.
- Prefer `get`/`list` commands before mutating commands.
- Prefer `--json` when output will be consumed by another command, script, or agent.
- Do not parse human-readable table output unless no JSON mode exists.
- Do not use high-impact commands as probes. See **High-Impact Commands** below.

---

## Dispatch Modes

EITS agents run in one of two dispatch modes:

- **`cli`** — interactive agent running in the current terminal/session
- **`sdk-cli`** — spawned or delegated agent running through the SDK CLI wrapper

Both modes use the **same `eits` command syntax**. Dispatch mode is informational — it tells you how the agent was launched, but does not change which commands or flags to use.

**Spawned agents do not inherit `EITS_PROJECT_ID`.** If project context matters, pass it explicitly in spawn instructions or use `--interpolate-env` with `$EITS_PROJECT_ID`.

---

## Quick Start: Task Lifecycle

```bash
# 1. Start work — creates task, links to session, sets In Progress atomically
eits tasks begin --title "What you're doing" [--description "..."] [-p <project_id>] [--priority <p>] [--tag <id|name>]
# --tag is repeatable: --tag bug --tag auth

# 2. OR claim an orchestrator-assigned task (ownership transfer — removes prior session links)
eits tasks claim <task_id>

# 3. Annotate after the fact
eits tasks annotate <task_id> --body "What changed, what was learned, what remains"

# 4. Finish (atomic: annotates + marks Done in one round-trip)
eits tasks complete <task_id> --message "What was done and why"

# 5. Log commits — auto-links using the current agent/session environment
eits commits create --hash <sha>
# Can also be done inline with complete (--commit is repeatable for multiple hashes):
eits tasks complete <task_id> --message "..." --commit <sha1> --commit <sha2>
# Commit response shape: {errors, commits, duplicates} — no top-level success field
```

### New vs existing tasks

| Goal | Command |
|---|---|
| Create a new task and start it | `eits tasks begin --title "..."` |
| Claim an orchestrator-assigned task | `eits tasks claim <id>` |
| `tasks begin --id <id>` | compatibility alias for `claim`; works but prefer `claim` |
| `tasks start <id>` | **deprecated** — prints a warning; use `claim` instead |

`tasks claim <id>` transfers ownership to the current session by removing prior session links. Use it only for orchestrator-assigned tasks or when intentionally taking over work.

---

## Required Task Rule

**You MUST have a task in state In Progress (state 2) before using write/edit tools.** The write hook checks for `state_id = 2` specifically — In Review does not satisfy it.

`eits tasks active` returns both In Progress and In Review tasks. Do not assume an In Review task unblocks file edits.

If blocked:

```bash
# Check what's active (use --json when you need task IDs for follow-up)
eits tasks active --json

# Start a new task
eits tasks begin --title "Describe the work"

# Or claim an existing task
eits tasks claim <task_id>
```

---

## Task Scoping

`eits tasks list` scopes to the current session when `EITS_SESSION_UUID` is set. Pass `--all` to see across sessions.

If `EITS_SESSION_UUID` is not set, `tasks begin`, `tasks annotate`, `tasks complete`, and `commits create` may not attach work to the intended session. Do not assume session linkage unless `EITS_SESSION_UUID` is present.

If `EITS_PROJECT_ID` is not set and a command requires a project, read `commands.md` for the command-specific flag — the flag name varies by subcommand (`-p` for most, `--project-id` for `sessions update` and `agents spawn`).

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

## Machine-Readable Output

When output will be consumed by another command, script, or agent, prefer `--json` if the command supports it. Do not parse human-readable tables or prose unless no JSON mode exists.

Commands with documented `--json` support in `commands.md` include: `tasks active`, `dm inbox`, `agents defs`, `teams status`, and `teams my-teams`.

Other commands may support `--json`; verify in `commands.md` or command help before using it.

---

## Session Identifier Shape

Session identifier support is **not uniform** across commands. Before passing a session ID:

- `eits sessions get <uuid>` — UUID only
- `eits dm --to <session_uuid_or_integer_id>` — UUID or integer
- `eits teams join --session <uuid|id>` — UUID or integer
- `eits agents spawn --parent-session-id <n>` — integer preferred (`$EITS_SESSION_ID`); UUID also accepted

Use `$EITS_SESSION_UUID` for UUID contexts, `$EITS_SESSION_ID` for integer contexts. When in doubt, read `commands.md` for the specific command.

---

## High-Impact Commands

These commands mutate shared state and are not reversible probes. Use read/list/get commands to inspect first.

- `eits agents spawn` — launches a live agent; use `--dry-run` first to validate flags and instructions
- `eits teams delete <id>` — destroys team and all membership records
- `eits teams broadcast <team_id>` — sends a message to every member of a team
- `eits teams leave <team_id> <member_id>` — removes a specific member; `member_id` is required
- `eits channels send --broadcast-team` — posts to a channel and fans out DMs to every team member
- `eits jobs cancel <id>` — cancels a running background job
- `eits notifications create` — fires a notification to users/sessions

For `eits agents spawn`, prefer `--instructions-file <path>` for long instructions to avoid shell escaping issues. Use `--interpolate-env` when spawned instructions need current orchestrator context (e.g. `$EITS_PROJECT_ID`, `$EITS_SESSION_ID`). Do not use `--interpolate-env` with secret-bearing variables.

For `agents spawn --team-id`, verify the spawned session actually joined the team. A bad team ID warns but spawn continues without team assignment.

---

## Resume Workflow

On resume, inspect current state before acting:

```bash
eits tasks active --json          # check for in-progress tasks; In Review does not unblock writes
eits dm inbox --since-session --json   # check for DMs since this session started; --unread does not exist
```

Do not create a new task or respond to stale DMs until current session context is confirmed.

---

## When More Detail Is Needed

Read `commands.md` before guessing command syntax for:
- sessions, agents, teams, dm, notes, channels, jobs, timer, prompts, projects, notifications
- any flag not shown in this file
- session identifier shape for a specific command

Read `gotchas.md` before answering questions about:
- environment variables or `EITS_URL` setup (exit 7 means connection failure, not unset URL)
- session/project scoping behavior
- blocked writes or hook behavior
- surprising JSON output shapes
- `self` alias behavior (`sessions get self` is broken — use `$EITS_SESSION_UUID`)
- DM inbox resume behavior (`--since-session`; `--unread` does not exist)
- `eits agents spawn` shell-escaping (`--instructions-file` avoids heredoc quoting issues; `--interpolate-env` expands orchestrator vars)
- completion detection (`teams status --wait`; do not DM-poll sessions)
