---
name: codex-dm
description: Send and respond to EITS direct messages from a Codex agent. Use when a DM arrives (starts with "DM from:") or when proactively messaging another session.
---

# Codex DM Protocol

## Receiving a DM

DMs arrive as:
```
DM from:<sender_name> (session:<from_session_uuid>) <message_body>
```

Reply immediately:
```bash
eits dm --to <from_session_uuid> --message "Your reply"
```

Rules: always respond; 1-3 sentences max.

---

## Sending a DM

`--to` accepts integer session ID or UUID — prefer integer:

```bash
eits dm --to <session_id> --message "text"    # integer ID (shorter)
eits dm --to <session_uuid> --message "text"  # UUID also works
```

**Send sequentially — never in parallel Bash calls.** One error cancels sibling calls.

---

## Environment

| Variable | Value |
|----------|-------|
| `EITS_SESSION_UUID` | Your session UUID (default `--from`) |
| `EITS_SESSION_ID` | Your session integer ID (use for `--to` targets) |
| `EITS_AGENT_UUID` | Your agent UUID |
