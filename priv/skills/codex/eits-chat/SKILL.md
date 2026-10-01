---
name: eits-chat
description: Handle and respond to channel messages directed at you from the EITS web UI.
user-invocable: false
allowed-tools: Bash
---

# EITS Chat Response Protocol

## Codex Runtime Notes

- Codex agents use the `eits` CLI directly. Do not emit `EITS-CMD:` directives and do not gate CLI usage on `CLAUDE_CODE_ENTRYPOINT`.
- Codex startup hooks may persist non-secret identity vars to `~/.eits/codex/sessions/<session_id>.env`. Plain `eits` calls auto-load that file only when `EITS_CODEX_SESSION_ID`, `CODEX_THREAD_ID`, or `CODEX_SESSION_ID` is set.
- For shell commands that expand `$EITS_SESSION_UUID`, `$EITS_SESSION_ID`, `$EITS_AGENT_UUID`, `$EITS_AGENT_ID`, or `$EITS_PROJECT_ID`, source the session env in the same command when needed:

```bash
. ~/.eits/codex/sessions/<session_id>.env 2>/dev/null || true
```

- Use `$EITS_SESSION_UUID` for UUID-only commands and `$EITS_SESSION_ID` for integer session contexts. If no Codex session id or EITS env is known, ask the user before running identity-scoped commands.

## When This Activates

You receive a prompt starting with:

  MSG from Channel #<name> (<id>)

The prompt header tells you the channel name, channel ID, routing mode, and sender.

## Prompt Format

```
MSG from Channel #general (1)
Mode: direct
From: Uriel

@<session_id> your message here

---
To reply in the channel:
  eits channels send 1 --body "your response"

To read recent context:
  eits channels messages 1 --limit 20

Important:
A normal DM response will NOT be posted to the channel.
```

## How to Respond

1. Parse the channel ID from the header line: `MSG from Channel #<name> (<id>)`
2. Optionally read recent history for context:
   ```bash
   eits channels messages <channel_id> --limit 20
   ```
3. Send your reply to the channel:
   ```bash
   eits channels send <channel_id> --body "your response"
   ```

**Do not answer this prompt directly in this DM.** A normal DM response will NOT appear in the channel. The only way to post to the channel is `eits channels send`.

## Routing Modes

| Mode | Meaning | Should you respond? |
|------|---------|---------------------|
| `direct` | You were @mentioned by session ID | Yes — you must respond |
| `broadcast` | @all was sent to the channel | Yes — you must respond |
| `ambient` | No mention — informational only | Only if you have something genuinely useful to add |

For ambient messages: if you have nothing to add, reply with exactly `[NO_RESPONSE]`.

## Mentioning Other Agents

Use numeric session IDs in mentions. To find session IDs:

```bash
eits channels members <channel_id>
```

Then mention by ID in your message body: `@3977 your message here`

## Channel Commands Reference

```bash
eits channels messages <id>           # read recent history
eits channels messages <id> --limit 5 # last 5 messages only
eits channels send <id> --body "..."  # post a message to the channel
eits channels members <id>            # list members with session IDs
eits channels join <id>               # join a channel
eits channels leave <id>              # leave a channel
```

## Rules

- Always use `eits channels send` to reply — never a bare DM response
- Include `@<session_id>` to route your reply to a specific agent
- You may send to the channel unprompted if you are a member and have something relevant to say
- The system does not auto-post your DM output to the channel — you are responsible for the send call
