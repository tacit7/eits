---
name: eits-cli
description: Use when an agent needs the correct eits CLI command syntax, flags, or dispatch mode. Triggers on: "how do I use eits", "what's the eits command for", "eits CLI reference", sessions/tasks/notes/commits/agents/jobs/timer/channels/teams/prompts/notifications flags, dispatch mode confusion (cli vs sdk-cli), EITS_URL setup, or any eits subcommand question.
user-invocable: true
allowed-tools: Bash
---

# EITS CLI Reference

The `eits` bash script is the sole interface to the EITS REST API. All agents — interactive (`cli`) and spawned (`sdk-cli`) — use it directly. EITS-CMD directives are **deprecated**.

## Required Environment

```bash
export EITS_URL=http://localhost:5001/api/v1
```

Set this before any `eits` command or you'll get exit 7.

---

## Task Lifecycle

```bash
# Preferred: create + link + start in one shot
eits tasks begin --title "Task name"

# OR: create first, then claim
eits tasks create --title "..." [--description "..."] [--project-id <id>]
eits tasks claim <id>

# Work...

# Finish: annotate + complete
eits tasks annotate <id> --body "What happened"
eits tasks complete <id> --message "Summary"

# OR: manually set state
eits tasks update <id> --state 4   # 4=In Review, 3=Done

# Other
eits tasks start <id>              # set state=2, link session (use on EXISTING tasks)
eits tasks list [--project-id <id>] [--state <id>] [--limit <n>]
eits tasks get <id>
```

### Workflow States
| ID | Name        |
|----|-------------|
| 1  | To Do       |
| 2  | In Progress |
| 4  | In Review   |
| 3  | Done        |

---

## Sessions

```bash
eits sessions list [--project-id <id>] [--status <status>] [--include-archived] [--limit <n>]
eits sessions get <uuid>
eits sessions update <uuid> [--status <s>] [--ended-at <iso8601>]
```

---

## Commits

```bash
eits commits create --hash <sha> [--hash <sha2> ...]
eits commits list [--session-id <uuid>] [--project-id <id>]
```

---

## DMs

```bash
eits dm --to <session_uuid_or_integer_id> --message "text"
```

Accepts both UUID and integer session ID.

---

## Notes

```bash
eits notes create --parent-type session --parent-id $EITS_SESSION_UUID --body "..."
eits notes create --parent-type task --parent-id <task_id> --body "..."
eits notes list [--parent-type <type>] [--parent-id <id>]
```

---

## Agents

```bash
eits agents list [--project-id <id>]
eits agents get <uuid>
eits agents spawn --project-id <id> --instructions "..."
eits agents update <uuid> [--status <s>]
```

---

## Teams

```bash
eits teams list
eits teams get <id>
eits teams create --name "..." [--project-id <id>]
eits teams join <id>
eits teams leave <id>
eits teams done
eits teams status <id>
eits teams update-member <team_id> [--status <s>]
```

---

## Channels

```bash
eits channels list [--project-id <id>]
eits channels send --channel <name> --message "..."
eits channels history <name> [--limit <n>]
```

---

## Jobs

```bash
eits jobs list [--queue <name>] [--state <s>]
eits jobs get <id>
eits jobs cancel <id>
```

---

## Timer

```bash
eits timer start --task-id <id>
eits timer stop
eits timer status
eits timer list [--task-id <id>]
```

---

## Prompts

```bash
eits prompts list [--project-id <id>] [--query <text>]
eits prompts get <id_or_slug> [--project-id <id>]
eits prompts create --name "..." --slug "..." --prompt-text "..."
```

---

## Projects

```bash
eits projects list
eits projects get <id>
eits projects create --name "..." [--git-remote <url>] [--repo-url <url>] [--branch <b>]
eits projects update <id> [--name <n>] [--active] [--inactive]
```

---

## Notifications

```bash
eits notifications list [--session-id <uuid>] [--unread]
eits notifications mark-read <id>
eits notifications mark-all-read
```

---

## Known Gotchas

1. **`eits agents spawn` exits 7** — `EITS_URL` not set. Always export it first.
2. **`tasks begin` on existing task duplicates** — use `tasks start <id>` for existing tasks; `begin` always creates a new one.
3. **Spawned agents need `--project-id` explicitly** — `EITS_PROJECT_ID` is not auto-injected into child processes.
4. **`dm --to` accepts both UUID and integer** — `$EITS_SESSION_ID` is integer; `$EITS_SESSION_UUID` is UUID. Either works.
5. **Write hook blocks if no active task** — run `eits tasks begin` before editing files.
6. **Agents commit to wrong branch** — always verify `git branch` before committing in a spawned agent.

---

## Environment Variables

| Variable              | Value / Purpose                          |
|-----------------------|------------------------------------------|
| `EITS_URL`            | `http://localhost:5001/api/v1` (required)|
| `EITS_SESSION_UUID`   | Current session UUID                     |
| `EITS_SESSION_ID`     | Current session integer ID               |
| `EITS_AGENT_UUID`     | Current agent UUID                       |
| `EITS_PROJECT_ID`     | Current project integer ID               |
