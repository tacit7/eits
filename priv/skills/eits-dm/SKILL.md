---
name: eits-dm
description: Send and respond to direct messages (DMs) between agents and sessions in EITS. Activates when a message starts with "DM from:" (incoming DM) or when an agent needs to DM another session/agent. Covers: parsing incoming DMs, replying, proactively sending messages.
user-invocable: false
---

# EITS DM Protocol

## Receiving a DM

DMs arrive as a prompt starting with:

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

**DM to waiting/idle/completed sessions returns HTTP 500.** The DM controller does not gate on session status — a 500 means the target session is in a non-active state, not a bug on your end. There is no workaround; the session is unreachable until it resumes. (Tracked: task 4968.)

**Send DMs sequentially — never in parallel Bash calls.** One error cancels sibling calls:

```bash
# Correct
eits dm --to $UUID_1 --message "..."
eits dm --to $UUID_2 --message "..."
```

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
