---
name: eits-cli-expert
description: Use when Codex needs exact EITS CLI command syntax, task/session/DM/commit workflow guidance, Rust CLI migration rules, EITS-CMD directive context, or troubleshooting for EITS_URL, session identity, hooks, and agent workflow commands. Trigger for questions about eits tasks, dm, sessions, commits, notes, whoami, CLI exit behavior, spawned/headless agents, and EITS-CMD vs direct CLI usage.
---

# EITS CLI Expert

Use this skill to choose precise EITS commands and explain EITS agent workflow mechanics.

## Operating Rule For Codex

Codex agents should call the `eits` CLI directly. Do not emit `EITS-CMD:` directives as a substitute for running `eits` from Codex.

The primary CLI is the Rust `eits` binary. Do not tell agents to call `eitsr` or `scripts/eits-extras`; the legacy fallback is an implementation detail.

## Current CLI Shape

The Rust-owned command families are:

- `eits tasks ...`
- `eits dm ...`
- `eits sessions ...`
- `eits commits ...`
- `eits notes ...`
- `eits whoami`

Rust-owned command stdout is JSON by default. Use `--pretty` for human-readable JSON and `--quiet` for bare IDs on supported mutations.

Use `eits --help` and `eits <command> --help` before giving detailed syntax for a command you have not recently verified.

## Identity And Environment

Prefer the process environment when present:

- `EITS_SESSION_UUID`
- `EITS_SESSION_ID`
- `EITS_PROJECT_ID`
- `EITS_AGENT_UUID`
- `EITS_URL`

If direct env vars are absent in Codex, EITS CLI may use Codex session env files under `~/.eits/codex/sessions/<session>.env` as process-local fallback config. Explicit process env vars win.

Use `eits whoami` to inspect the active identity.

## Common Commands

Start work:

```bash
eits tasks begin --title "Task name"
```

Claim an existing task:

```bash
eits tasks begin --id <task_id>
```

Annotate a task:

```bash
eits tasks annotate <task_id> --body "What changed or what you found"
```

Complete a task atomically:

```bash
eits tasks complete <task_id> --message "What happened"
```

Complete and link commits:

```bash
eits tasks complete <task_id> --message "What happened" --commit <sha>
```

Track commits independently:

```bash
eits commits create --hash <sha>
```

Send a DM:

```bash
eits dm --to <session_uuid_or_id> --message "Message text"
```

Read DMs:

```bash
eits dm inbox
eits dm read <dm_id>
eits dm wait --timeout <seconds>
```

Inspect a session:

```bash
eits sessions get <uuid-or-id>
eits sessions get self
```

Mark the current session complete:

```bash
eits sessions complete
```

## Task Workflow Rules

Use `eits tasks begin` instead of separate create/start/link steps when beginning new work. It creates or claims a task, links it to the current session, and sets it In Progress.

Use `eits tasks complete` when possible. It annotates and closes in one command.

Workflow state IDs:

| ID | State |
| --- | --- |
| 1 | To Do |
| 2 | In Progress |
| 4 | In Review |
| 3 | Done |

Use `eits tasks states` when aliases or IDs are unclear.

## EITS-CMD Context

`EITS-CMD:` directives are for Claude/headless spawned-agent contexts where the host intercepts output in-process. They are not a Codex CLI feature.

If explaining or debugging a Claude/headless flow, these directive forms may matter:

```text
EITS-CMD: task begin <title>
EITS-CMD: task done <id>
EITS-CMD: task annotate <id> <body>
EITS-CMD: dm --to <session_uuid> --message "<text>"
EITS-CMD: commit <sha>
```

Warn users that malformed directives can fail without useful feedback and that directive processing may be asynchronous.

## Troubleshooting

When an EITS command fails or behaves unexpectedly:

1. Run `eits whoami` to verify session and project identity.
2. Check `EITS_URL` if API connectivity is suspect.
3. Run the exact subcommand with `--help` to verify flags.
4. Confirm the task is linked to the current session before completing or annotating it.
5. Use `eits sessions get self` to inspect current session state.
6. For Codex-specific env issues, check whether `~/.eits/codex/sessions/<session>.env` exists and whether direct `EITS_*` vars override it.

Give copy-pasteable commands. Avoid pseudocode when the user asks how to operate EITS.
