---
name: eits-chat
description: Handle and respond to channel messages directed at you from the EITS web UI.
user-invocable: false
allowed-tools: Bash
---

# EITS Chat Response Protocol

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
