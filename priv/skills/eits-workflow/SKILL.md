---
name: eits-workflow
description: EITS task, commit, and note workflow for agents. Use when an agent needs to log work, create/claim/complete tasks, log commits, or add notes during a session. Covers both sdk-cli (EITS-CMD directives) and cli (eits script) entrypoints. Triggers on: "begin a task", "log this commit", "mark task done", "add a note", task lifecycle questions, or any EITS-CMD usage.
user-invocable: true
allowed-tools: Bash
argument-hint: "[task|commit|note|dm]"
---

# EITS Workflow

## Entrypoint Check First

```bash
echo "$CLAUDE_CODE_ENTRYPOINT"
```

| Value | Mode | Use |
|-------|------|-----|
| `sdk-cli` | Spawned/headless agent | **EITS-CMD directives** in text output |
| `cli` | Interactive session | **eits CLI script** |

---

## sdk-cli — EITS-CMD Directives

AgentWorker intercepts these lines from stdout. Never use the `eits` bash script when running as `sdk-cli`.

```
EITS-CMD: task begin <title>
EITS-CMD: task done <id>
EITS-CMD: task annotate <id> <body>
EITS-CMD: note <body>
EITS-CMD: note task <id> <body>
EITS-CMD: dm --to <session_uuid> --message "text"
EITS-CMD: commit <hash>
```

### Feedback Messages

Every EITS-CMD directive sends a feedback message back to your session:

- **Success**: `[EITS-CMD ok] task begun id=42 title=Fix bug` — contains IDs you need for follow-up commands
- **Error**: `[EITS-CMD error] task done: {:not_linked, 99}` — tells you exactly what went wrong

**You MUST wait for the feedback message before using returned IDs.** For example, after `EITS-CMD: task begin Fix something`, wait for the `[EITS-CMD ok] task begun id=<N>` response before emitting `EITS-CMD: task annotate <N> ...` or `EITS-CMD: task done <N>`. Do not guess task IDs.

---

## cli — eits Script

```bash
# Task lifecycle
eits tasks begin --title "Task name"          # create + start in one shot
eits tasks claim <id>                          # in-progress, self-assign, link session
eits tasks complete <id> --message "Summary"  # annotate + done + team status update
eits tasks annotate <id> --body "..."
eits tasks update <id> --state 4              # 4 = In Review

# Commits
eits commits create --hash <hash1> [--hash <hash2>]

# Notes
eits notes create --parent-type session --parent-id $EITS_SESSION_UUID --body "..."
eits notes create --parent-type task --parent-id <id> --body "..."

# DMs
eits dm --to <session_uuid> --message "text"
```

---

## Task Lifecycle

### Preferred (2-command)
```bash
eits tasks create --title "..." --description "..."
eits tasks claim <task_id>
# ... do work ...
eits tasks complete <task_id> --message "What was done"
```

### Legacy fallback
```bash
eits tasks start <id>
# ... do work ...
eits tasks annotate <id> --body "Summary"
eits tasks update <id> --state 4
```

### Workflow states
| ID | Name |
|----|------|
| 1 | To Do |
| 2 | In Progress |
| 4 | In Review |
| 3 | Done |

---

## Rules

- **You MUST have a task in_progress before editing any files.**
- The Stop hook (`.claude/hooks/eits-task-gate.sh`) blocks exit if any task is in state 2 (In Progress) linked to your session. Complete the task sequence before stopping.
- Log commits after every `git commit`: `eits commits create --hash <hash>`
- Annotate tasks before completing them — the annotation is the handoff record.

---

## Environment Variables

| Var | Purpose |
|-----|---------|
| `EITS_SESSION_UUID` | Your session UUID |
| `EITS_AGENT_UUID` | Your agent UUID |
| `EITS_PROJECT_ID` | Your project ID |
| `EITS_URL` | `http://localhost:5001/api/v1` |
