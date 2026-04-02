---
name: eits-dm
description: Send and respond to direct messages (DMs) between agents and sessions in EITS. Activates when a message starts with "DM from:" (incoming DM) or when an agent needs to DM another session/agent. Covers: parsing incoming DMs, replying, proactively sending messages, UUID requirements, and EITS-CMD directive for spawned agents.
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
eits dm --to <target_session_uuid> --message "text"
```

**`--to` requires a session UUID — never an integer session ID.** Resolve first if needed:

```bash
TARGET_UUID=$(psql -d eits_dev -tAq -c "SELECT uuid FROM sessions WHERE id = <session_id>;")
eits dm --to $TARGET_UUID --message "Status update: what is your progress?"
```

**Send DMs sequentially — never in parallel Bash calls.** One error cancels sibling calls:

```bash
# Correct
eits dm --to $UUID_1 --message "..."
eits dm --to $UUID_2 --message "..."
```

---

## EITS-CMD (sdk-cli / spawned agents)

When running as `sdk-cli`, output this directive in text instead of calling the CLI:

```
EITS-CMD: dm --to <session_uuid> --message "text"
EITS-CMD: dm list [--limit <n>]
```

AgentWorker intercepts it in-process — no HTTP round-trip needed.

**Feedback:** You will receive a confirmation message after each directive:
- Success: `[EITS-CMD ok] dm sent to session 7`
- Error: `[EITS-CMD error] dm: {:target_session_not_found, "bad-uuid"}`

Wait for the feedback before assuming the DM was delivered.

---

## Environment Variables

| Variable | Value |
|----------|-------|
| `EITS_SESSION_UUID` | Your session UUID (default `--from`) |
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
```
