---
name: codex-workflow
description: EITS task, commit, and annotate workflow for Codex agents. Use when beginning a task, logging a commit, marking work done, or managing EITS task lifecycle. Codex uses eits CLI directly — no EITS-CMD directives.
---

# Codex EITS Workflow

Use the `eits` CLI for all EITS operations.

---

## Session Status

Codex hooks handle `working`/`stopped` transitions automatically via `.codex/hooks.json`. If hooks are not active, set status manually:

```bash
eits sessions update $EITS_SESSION_UUID --status working   # start of turn
eits sessions update $EITS_SESSION_UUID --status stopped   # end of turn
eits sessions update $EITS_SESSION_UUID --status waiting   # spawned agent done
eits sessions update $EITS_SESSION_UUID --status completed # interactive session done
```

---

## Task Lifecycle

```bash
# Canonical: create + link + start in one shot
eits tasks begin --title "..."
# ... do work ...
eits tasks complete <task_id> --message "What was done"
```

Fallback (existing task or if `complete` fails):
```bash
eits tasks start <id>       # sets state=2, links session — use on EXISTING tasks
# ... do work ...
eits tasks annotate <id> --body "Summary"
eits tasks update <id> --state done   # aliases: done, start, in-review, todo; numeric also works
```

States: `1` To Do · `2` In Progress · `4` In Review · `3` Done

---

## Commits

After every `git commit`, log the hash. The PostToolUse hook does this automatically if `.codex/hooks.json` is active. If not:

```bash
HASH=$(git -C $EITS_PROJECT_DIR rev-parse HEAD)
MSG=$(git log -1 --pretty=%s HEAD)
eits commits create --hash $HASH --message "$MSG"
```

---

## Annotation (mandatory before stopping)

The Stop hook enforces this — it exits 2 if a task is in-progress with no annotation. Always annotate before declaring a turn done:

```bash
eits tasks annotate <id> --body "What was done, what files changed"
```

---

## File System Guard

`rm` is aliased to `rm-trash` and **follows symlinks**. Use `unlink` on symlinks:

```bash
unlink deps    # not: rm deps
unlink _build  # not: rm _build
```

---

## DMs

```bash
eits dm --to <session_uuid_or_integer_id> --message "text"
```

`--to` accepts both UUID and integer session ID. Send sequentially — never in parallel Bash calls.

---

## Rules

- Run `eits tasks begin` before editing any files (`begin` > `create + claim`).
- Log every commit — hook does it automatically, but verify.
- Annotate before completing; Stop hook enforces it.
- Use `unlink`, not `rm`, on symlinks.
