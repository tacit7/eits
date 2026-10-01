---
name: eits-team-member
description: >
  Use when you are a spawned EITS team member or your instructions include
  team_id, --member-name, an assigned task id, "claim task", or "DM back when
  done". Provides the required team-member runtime protocol: inbox checkpoints,
  task claim, no duplicate tasks, validation, completion, explicit DM-back, and
  final inbox check.
allowed-tools: Bash
---

# EITS Team Member

You are a member of an EITS team when your instructions include a `team_id`,
`--member-name`, an assigned task id, or wording like "claim task" / "DM back
when done".

This skill is the mandatory team-member protocol. For implementation discipline
inside a code worktree, also use `eits-team-worker`.

## Required Sequence

Run this sequence exactly for assigned team work:

```bash
eits dm inbox --since-session --team-only --json
eits tasks claim <task_id>
eits dm inbox --since-session --team-only --json
# do the assigned work
# run validation requested by the task or required by the repo
eits dm inbox --since-session --team-only --json
eits tasks complete <task_id> --message "What happened"
eits dm --to <ORCHESTRATOR_SESSION_ID> --message "done task=<task_id> result=<summary> branch=<branch-or-pr> commit=<sha-or-none>"
eits dm inbox --since-session --team-only --json
```

`eits tasks complete` is not enough. It marks the task done but does **not** tell
the orchestrator what branch, commit, result, or blocker to act on. The explicit
DM-back is required even when the task is complete and member status is done.

## Task Claim Rules

- Claim the assigned task before editing files.
- Use `eits tasks claim <task_id>` for orchestrator-created team tasks.
- Do not run `eits tasks begin --title ...` for pre-created team work; that
  creates a duplicate task.
- If no task id was assigned, DM the orchestrator and wait. Do not invent work.

## Inbox Rules

CLI/headless sessions do not receive live DMs automatically. Poll the inbox:

- before claiming
- after claiming
- after major state transitions
- before completing
- after the done/blocker DM

Use:

```bash
eits dm inbox --since-session --team-only --json
```

Reply to actionable DMs with:

```bash
eits dm --to <sender_session_uuid_or_id> --message "short reply"
```

Send DMs sequentially. Do not send multiple `eits dm` commands in parallel.

## Done DM Format

Use a compact, parseable completion DM:

```text
done task=<task_id> result=<summary> branch=<branch-or-pr> commit=<sha-or-none>
```

If blocked or incomplete, say so explicitly:

```text
blocked task=<task_id> reason=<specific blocker> branch=<branch> commit=<sha-or-none>
```

## Validation And Commit

- Run the validation requested by the task instructions.
- If the repository requires compile/test checks, run them before completing.
- If you commit, log each commit with `eits commits create --hash <sha>`.
- If you do not commit, say `commit=none` in the DM and explain where the
  uncommitted work lives.

## Hard Rules

- Claim first.
- Do not create duplicate tasks.
- Poll inbox at checkpoints.
- Complete the task with `eits tasks complete`.
- DM the orchestrator explicitly after completion or blockage.
- Check inbox again after the DM.
