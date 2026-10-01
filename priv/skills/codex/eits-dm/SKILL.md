---
name: eits-dm
description: Send, poll, and respond to EITS direct messages from a Codex agent. Use when a DM arrives (starts with "DM from:"), when proactively messaging another session, or when a Codex/CLI agent needs to check its DM inbox for multi-agent coordination.
---

# Codex DM Protocol

For Codex sessions, source `~/.eits/codex/sessions/<session_id>.env` in the
same Bash command before using `$EITS_SESSION_UUID` or `$EITS_SESSION_ID` shell
expansion. Plain `eits` CLI calls auto-load the session-specific file only when
`EITS_CODEX_SESSION_ID`, `CODEX_THREAD_ID`, or `CODEX_SESSION_ID` is set. If no
session id is known, ask the user for it.

## Delivery Modes

EITS has two DM delivery paths:

- App-backed sessions have a worker/GenServer mailbox. DMs queue there and are
  delivered into the live session automatically.
- CLI/Codex terminal sessions do not have that live mailbox. DMs are durable in
  EITS, but the agent must poll its inbox with `eits dm inbox`.

For Codex/CLI sessions, do not assume silence means no messages. Check the inbox
at session start/resume and while coordinating with other agents.

## Receiving a DM

In app-backed sessions, DMs arrive as:
```
DM from:<sender_name> (session:<from_session_uuid>) <message_body>
```

Reply immediately:
```bash
eits dm --to <from_session_uuid> --message "Your reply"
```

Rules: always respond; 1-3 sentences max.

---

## CLI Inbox Polling

Use this when running in Codex/CLI, when resuming, or when another agent may
have DM'd you:

```bash
eits dm inbox --since-session --json
```

Useful variants:

```bash
eits dm inbox --limit 50
eits dm inbox --since "2026-04-30T12:00:00Z"
eits dm inbox --from <session_uuid_or_integer_id>
eits dm inbox --team-only --json
eits dm read <message_id>
```

Rules:

- Omit `--session` when reading your own inbox; it resolves from your EITS env.
- Use `--since-session` on resume to avoid stale messages from prior runs.
- Use `--team-only` during team orchestration.
- `--unread` does not exist; there is no read/ack field.
- For repeated polling in one turn, remember the latest handled `inserted_at` or
  message id and use `--since <timestamp>` next time.
- Use `eits dm read <message_id>` when table output truncates the body.
- Reply to every actionable DM with `eits dm --to <sender_session_uuid_or_id>
  --message "..."`.

---

## Sending a DM

```bash
eits dm --to <session_uuid_or_integer_id> --message "text"
```

`--to` accepts both UUID and integer session ID. Use `$EITS_SESSION_UUID` or `$EITS_SESSION_ID` — both work.

**Send sequentially — never in parallel Bash calls.** One error cancels sibling calls.

---

## Multi-Agent Communication Pattern

When coordinating agents:

1. Send DMs sequentially.
2. Prefer `eits teams status <team_id> --wait` for completion tracking.
3. After `--wait` returns, run `eits dm inbox --since-session --team-only --json`
   to collect worker replies.
4. If waiting for a specific response, use `eits dm wait --since <timestamp>`
   when available instead of manual sleep loops.

---

## Environment

| Variable | Value |
|----------|-------|
| `EITS_SESSION_UUID` | Your session UUID (default `--from`); `--to` also accepts `$EITS_SESSION_ID` |
| `EITS_AGENT_UUID` | Your agent UUID |
