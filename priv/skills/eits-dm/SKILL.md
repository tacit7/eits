---
name: eits-dm
description: >-
  Send, poll, and respond to direct messages (DMs) between agents and sessions in
  EITS. Activates when a message starts with "DM from:" (incoming DM), when an
  agent needs to DM another session/agent, or when a CLI/headless agent needs to
  check its inbox for multi-agent coordination. Covers parsing incoming DMs,
  inbox polling, replying, and proactive sends.
---

# EITS DM Protocol

## Delivery Modes

EITS has two DM delivery paths:

- App-backed sessions have a worker/GenServer mailbox. DMs queue there and are
  delivered into the live session automatically.
- CLI/headless sessions do not have that live mailbox. DMs are durable in EITS,
  but the agent must poll its inbox with `eits dm inbox`.

For CLI/headless sessions, do not assume silence means no messages. Check the
inbox at session start/resume and while coordinating with other agents.

## Receiving a DM

In app-backed sessions, DMs arrive as a prompt starting with:

```
DM from:<sender_name> (session:<from_session_uuid>) <message_body>
```

Parse: sender name, `from_session_uuid`, message body. Reply immediately.

---

## Replying

```bash
eits dm --to <from_session_uuid> --message "Your reply here"
```

`--from` defaults to `$EITS_SESSION_UUID` — omit it.

Rules:
- **Always respond.** Unanswered DMs block the sender.
- Keep it short — 1-3 sentences max.
- Do NOT use i-speak or i-chat-send — use `eits dm`.

---

## Sending a DM (proactive)

```bash
eits dm --to <session_uuid_or_integer_id> --message "text"
```

`--to` accepts both UUID and integer session ID. Use `$EITS_SESSION_UUID` or `$EITS_SESSION_ID` — both work.

DMs are durable. A completed or failed CLI/headless session may not have a live
worker, but `eits dm` should still store the message so the session can read it
from `eits dm inbox` if it resumes or is inspected later.

**Send DMs sequentially — never in parallel Bash calls.** One error cancels sibling calls:

```bash
# Correct
eits dm --to $UUID_1 --message "..."
eits dm --to $UUID_2 --message "..."
```

---

## Inbox Polling Checkpoints

Use `eits dm inbox --since-session --team-only --json`:

- after resuming a session, run `eits work checkpoint` first to confirm your current task/team/git context, then poll the inbox
- before claiming work
- after major state transitions
- before `eits tasks complete`
- after sending a completion DM, to catch follow-up work

Use `eits work status` or `eits work checkpoint` when the message flow changes your ownership, team membership, or git state. It is the fast local snapshot; inbox polling is still the durable source of team messages.

---

## Listing Inbound DMs (inbox polling)

Use this when running in CLI/headless mode, when resuming, when you know agents
DM'd you, or when you cannot check the web UI:

```bash
eits dm inbox                                       # inbox for current session (default limit 20)
eits dm inbox --session <uuid|id>                   # inbox for any session
eits dm inbox --limit 50                            # up to 100 max
eits dm inbox --since "2026-04-30T12:00:00Z"        # only messages after timestamp
eits dm inbox --since-session                       # only messages since this session started
eits dm inbox --from <session_id>                   # filter by sender (UUID or integer ID)
eits dm inbox --team-only                           # only DMs from sessions in shared teams
eits dm inbox --json                                # machine-readable output
eits dm read <message_id>                           # full body when table output truncates it
eits dm wait [--since <timestamp>] [--team-only]     # long-poll for the next DM
# alias: eits dm list (identical)
```

**Use `--since-session` when resuming** — DMs have no read/ack state, so prior-session worker DMs replay on every resume. `--since-session` resolves the session's `created_at` from the API and uses it as a `--since` filter, suppressing stale DMs automatically.

Rules:
- Omit `--session` when reading your own inbox; it resolves from your EITS env.
- Use `--team-only` during team orchestration.
- `--unread` does not exist; there is no read/ack field.
- For repeated polling in one turn, remember the latest handled `inserted_at` or
  message id and use `--since <timestamp>` next time.
- Reply to every actionable DM with `eits dm --to <sender_session_uuid_or_id>
  --message "..."`.

Returns `{session_id, session_uuid, count, messages[]}`. Messages are ordered oldest-first.

---

## Multi-Agent Communication Pattern

When coordinating agents:

1. Send DMs sequentially.
2. Prefer `eits teams status <team_id> --wait` for completion tracking.
3. After `--wait` returns, run `eits dm inbox --since-session --team-only --json`
   to collect worker replies.
4. If waiting for a specific response, use `eits dm wait --since <timestamp> --team-only`
   when available instead of manual sleep loops.

---

## Environment Variables

| Variable | Value |
|----------|-------|
| `EITS_SESSION_UUID` | Your session UUID (default `--from`); `--to` also accepts `$EITS_SESSION_ID` |
| `EITS_AGENT_UUID` | Your agent UUID |

---

## Example — Incoming

```
DM from:coordinator (session:f47ac10b-...) What's the status of the auth module?
```

```bash
eits dm --to f47ac10b-... --message "Auth module 80% done — JWT validation complete, session persistence in progress."
```

## Example — Proactive (orchestrator nudging an agent)

```bash
eits dm --to $AGENT_UUID --message "Task #817 is still in-progress. Complete the task completion sequence and DM back."
eits dm --to 2920 --message "Done. PR merged."   # integer ID also works
```
