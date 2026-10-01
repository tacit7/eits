---
name: eits-workflow
description: "EITS task, commit, and note workflow for Codex agents. Codex always uses the eits CLI directly with no CLAUDE_CODE_ENTRYPOINT check and no EITS-CMD directives. Use when beginning a task, logging a commit, marking work done, adding a note, or handling task lifecycle questions."
---

# Codex EITS Workflow

Codex agents use the `eits` CLI directly for EITS operations.

## Codex Env Bootstrap

Codex startup hooks persist EITS identity to
`~/.eits/codex/sessions/<session_id>.env`. The `eits` CLI auto-loads that
session-specific file when `EITS_CODEX_SESSION_ID`, `CODEX_THREAD_ID`, or
`CODEX_SESSION_ID` is set. If no session id is known, ask the user for it.
For commands that rely on shell expansion of `$EITS_SESSION_UUID`,
`$EITS_AGENT_UUID`, or `$EITS_PROJECT_ID`, source the session-specific file in
the same Bash command:

```bash
. ~/.eits/codex/sessions/<session_id>.env 2>/dev/null || true
```

## Session Status

Codex hooks handle `working`/`idle`/`waiting`/`compacting` transitions automatically via `.codex/hooks.json` when `~/.codex/config.toml` has `features.hooks = true`. If hooks are not active, set status manually:

```bash
eits sessions update $EITS_SESSION_UUID --status working   # start of turn
eits sessions update $EITS_SESSION_UUID --status idle      # interactive turn stopped; resumable
eits sessions update $EITS_SESSION_UUID --status waiting   # explicitly blocked or waiting on external input
eits sessions update $EITS_SESSION_UUID --status compacting # context compaction in progress
eits sessions update $EITS_SESSION_UUID --status completed # interactive session done
eits sessions update $EITS_SESSION_UUID --status failed    # unrecoverable error
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
