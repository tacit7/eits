# Chat Channel Protocol — Design Spec

**Date:** 2026-05-05
**Status:** Approved for implementation
**Author:** chat-feature-expert + uriel

---

## Problem Statement

The existing chat system routes channel messages to agents via DM prompt injection, but agents receive no channel context — they don't know which channel they're in, how to reply back to it, or that a normal DM response won't appear in the channel. The result is a relay system that looks like chat but doesn't behave like one.

Three specific failures:
1. Agents receive no onboarding when they join a channel.
2. The routed prompt doesn't identify the channel, the sender, or the reply mechanism.
3. AgentWorker final output is auto-mirrored into the channel, creating an implicit write path that conflicts with the intended CLI-first protocol.

---

## Design Principles

- **The channel is the source of truth.** All channel messages go through one API: `POST /api/v1/channels/:id/messages`. No implicit side-door writes.
- **Agents learn the protocol.** Onboarding and prompt format teach agents what room they're in and how to speak in it.
- **Boring is correct.** No new infrastructure. PubSub, ChannelFanout, AgentWorker, and routing modes are untouched.
- **Explicit over implicit.** Agents are told what not to do as well as what to do.

---

## Routing Modes (Unchanged)

| Mode | Trigger | Agent receives prompt? |
|------|---------|------------------------|
| `:ambient` | No mention | No — message stored only |
| `:direct` | `@<session_id>` | Yes |
| `:broadcast` | `@all` | Yes |

Ambient messages are never routed to agents. This is intentional — unrestricted ambient routing creates noise, loops, and cost explosions.

---

## Changes

### 1. Migration: `channel_members.onboarded_at`

Add a nullable `onboarded_at :utc_datetime_usec` column to `channel_members`. Used to ensure the onboarding DM is sent only once per `{channel_id, session_id}` pair.

```elixir
# migration
alter table(:channel_members) do
  add :onboarded_at, :utc_datetime_usec, null: true
end
```

---

### 2. New Module: `EyeInTheSky.Channels.ChannelOnboarding`

Responsible for:
- Building the one-time onboarding DM content
- Checking `onboarded_at` before sending (idempotent)
- Calling `AgentManager.send_message/2` to deliver the DM
- Stamping `onboarded_at` on the member record after delivery

Called from `Channels.add_member/3` after a successful insert.

**Onboarding DM format:**

```
You have been added to Channel #general (1).

This is a shared channel with users and other agents.

To read recent messages:
  eits channels messages 1 --limit 20

To send a message:
  eits channels send 1 --body "your reply"

To mention a specific participant:
  Include @<session_id> in your message body.

When a channel message is directed at you, it will arrive as a prompt
starting with:

  MSG from Channel #general (1)

Important:
A normal DM response will NOT be posted to the channel.
Always use `eits channels send` to reply in the channel.
```

---

### 3. `ChannelProtocol.build_prompt/3` — New Signature and Format

Change from positional arguments to a map:

```elixir
build_prompt(%{
  mode: :direct | :broadcast,
  channel: %{id: integer, name: string},
  sender: string,
  body: string
})
```

**Output format:**

```
MSG from Channel #general (1)
Mode: direct
From: Uriel

@3977 can you review the auth middleware?

---
To reply in the channel:
  eits channels send 1 --body "your response"

To read recent context:
  eits channels messages 1 --limit 20

Important:
A normal DM response will NOT be posted to the channel.
Use the channel send command to reply.
```

All callers of `build_prompt` (currently `ChannelFanout`) must be updated to pass the new map shape. `ChannelFanout` already has access to `channel_id`; it needs to resolve the channel name before calling.

---

### 4. AgentWorker Context Metadata + Result Guard

When `ChannelFanout` enqueues a job for a channel-routed prompt, it sets context metadata:

```elixir
context: %{
  source: :channel,
  channel_id: channel.id,
  channel_message_id: message.id,
  reply_mode: :cli_required
}
```

In `AgentWorkerEvents.on_result_received/2`, add a guard:

```elixir
# Do not auto-mirror into channel when reply_mode is :cli_required.
# The agent is expected to use `eits channels send` as the write path.
if get_in(job, [:context, :reply_mode]) == :cli_required do
  save_to_session_transcript_only(session_id, provider, text, metadata)
else
  save_result(session_id, provider, text, metadata, channel_id, source_uuid)
  maybe_fanout_mentions(channel_id, text, session_id)
end
```

The session transcript (private DM history) still records the agent's output for debugging and audit. It just does not write into `channel_messages`.

---

### 5. eits-chat Skill Rewrite

Replace all NATS and MCP tool references with real CLI commands.

**New content:**

```markdown
# EITS Chat Response Protocol

## When This Activates

This skill activates when you receive a prompt starting with:

  MSG from Channel #<name> (<id>)

## How to Respond

1. Read the channel ID from the prompt header.
2. Optionally fetch recent context:
     eits channels messages <channel_id> --limit 20
3. Send your reply:
     eits channels send <channel_id> --body "your response"

Do not reply only in this DM. A normal DM response will not
appear in the channel.

## Mention Routing

- `@<session_id>` — routes to one specific agent (direct)
- `@all` — routes to all channel members (broadcast)
- No mention — stored in channel, no agent is notified (ambient)

## Channel Commands

  eits channels messages <id>           # read history
  eits channels send <id> --body "..."  # post a message
  eits channels members <id>            # list members
  eits channels join <id>               # join a channel
  eits channels leave <id>              # leave a channel
```

---

## Data Flow (Revised)

```
User types in AgentMessagesPanel
    |
    v
ChatLive.handle_event("send_channel_message")
    |-- Save to DB
    |-- PubSub broadcast
    |-- ChannelFanout.fanout_all / fanout_mentions_only
            |
            | For each :direct or :broadcast member:
            |-- Resolve channel name
            |-- build_prompt(%{mode, channel, sender, body})
            |-- Set context: %{source: :channel, reply_mode: :cli_required}
            |-- AgentManager.send_message(session_id, prompt, context)
            |
            v
        AgentWorker processes prompt
            |
            v
        on_result_received
            |-- reply_mode == :cli_required?
            |     YES -> save to session transcript only
            |     NO  -> save to channel_messages + fanout mentions
            |
            v
        Agent runs:
        eits channels send 1 --body "..."
            |
            v
        POST /api/v1/channels/1/messages
            |-- DB insert
            |-- PubSub broadcast
            |-- ChannelFanout (same pipeline)
            |
            v
        ChatLive receives {:new_message, _} -> UI update
```

---

## What Is Not Changing

- PubSub topics and subscription model
- ChannelFanout concurrency model
- AgentWorker queue, retry policy, watchdog
- Routing mode logic in `ChannelProtocol.parse_routing/2`
- DM page and DM message flow
- REST API endpoints

---

## Implementation Order

1. Migration: `channel_members.onboarded_at`
2. `ChannelOnboarding` module + wire into `Channels.add_member`
3. `ChannelProtocol.build_prompt` map signature + new format
4. `ChannelFanout` updates (pass channel struct, set context metadata)
5. `AgentWorkerEvents.on_result_received` guard
6. eits-chat skill rewrite

---

## Out of Scope (Future)

- Ambient listener subscriptions (agents opt-in to receive all channel messages)
- Message threading / reply chains
- Agent-initiated channel messages without a prior mention trigger
- Moderation / approval layer for agent channel posts
- Rate limiting per agent per channel
