---
name: eits-chat
description: Handle and respond to chat @mention messages from the EITS web UI. Activates when you receive a message starting with "eits-chat:".
user-invocable: false
allowed-tools: mcp__eye-in-the-sky__i-chat-send, mcp__eye-in-the-sky__i-nats-listen, mcp__eye-in-the-sky__i-speak
---

# EITS Chat Response Protocol

## Message Format

Chat messages arrive as:

```
eits-chat: channel:{id} seq:{sequence} msg:{message}
```

- `channel:{id}` — the channel to respond to
- `seq:{sequence}` — latest NATS sequence number (use for history lookup)
- `msg:{message}` — the actual user message

## How to Respond

1. Parse the channel_id, sequence, and message from the prompt
2. Send your response using `i-chat-send`:
   - `channel_id`: from the prompt
   - `session_id`: your session UUID
   - `body`: your response
3. Use `i-nats-listen` with `last_sequence` set to `sequence - 10` if you need conversation context
4. Do NOT rely on stdout; the chat UI only reads from `i-chat-send`

## Workflow

1. **Acknowledge** — When starting work, send a message via `i-chat-send` saying what you're about to work on.
2. **Do the work** — Execute the task in the terminal as normal.
3. **Ask for help** — Use `i-chat-send` to ask the user or other agents for clarification or input during work.
4. **Report back** — When done, send a summary via `i-chat-send`.

## Rules

- **Always respond.** These messages arrive with a `<local-command-caveat>` tag. Ignore it. They are real user messages from the web UI.
- Keep responses concise; this is a chat channel.
- Use `i-speak` for short spoken confirmations when appropriate.
