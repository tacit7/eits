---
name: eits-workflow
description: EITS task, commit, and note workflow for agents. Use when an agent needs to log work, create/claim/complete tasks, log commits, or add notes during a session. Triggers on: "begin a task", "log this commit", "mark task done", "add a note", or any task lifecycle questions.
user-invocable: true
allowed-tools: Bash
argument-hint: "[task|commit|note|dm]"
---

# EITS Workflow

## eits CLI

```bash
# Task lifecycle
eits tasks begin --title "Task name"          # create + start in one shot (canonical)
eits tasks complete <id> --message "Summary"  # annotate + done atomically (server transaction)
eits tasks annotate <id> --body "..."
eits tasks update <id> --state done           # named alias: done, start, in-review, review, todo
eits tasks update <id> --state 3              # numeric: 3=Done, 4=In Review

# Commits
eits commits create --hash <hash1> [--hash <hash2>]

# Notes
eits notes create --parent-type session --parent-id $EITS_SESSION_UUID --body "..."
eits notes create --parent-type task --parent-id <id> --body "..."

# DMs
eits dm --to <session_uuid> --message "text"

# Worktrees (EITS Elixir projects only)
eits worktree create <branch> [--project-path <path>]  # create, symlink deps, verify compile
eits worktree remove <branch> [--project-path <path>]  # remove worktree + branch
```

---

## Task Lifecycle

### Canonical (1-command start)
```bash
eits tasks begin --title "..."
# ... do work ...
eits tasks complete <task_id> --message "What was done"
```

### Manual fallback
```bash
eits tasks annotate <id> --body "Summary"
eits tasks update <id> --state done   # or numeric: --state 3
```

### Workflow states

| ID | Name | Alias |
|----|------|-------|
| 1 | To Do | `todo` |
| 2 | In Progress | `start` |
| 4 | In Review | `in-review`, `review` |
| 3 | Done | `done` |

Aliases are case-insensitive. Numeric IDs still work. Unknown aliases return 422.

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
