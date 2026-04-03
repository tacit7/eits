---
name: eits-workflow
description: EITS task, commit, and note workflow for agents. Use when an agent needs to log work, create/claim/complete tasks, log commits, or add notes during a session. Triggers on: "begin a task", "log this commit", "mark task done", "add a note", task lifecycle questions.
user-invocable: true
allowed-tools: Bash
argument-hint: "[task|commit|note|dm]"
---

# EITS Workflow

All agents — interactive (`cli`) and spawned (`sdk-cli`) — use the `eits` CLI script.

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
