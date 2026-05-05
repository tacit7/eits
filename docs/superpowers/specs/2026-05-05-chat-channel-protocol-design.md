# Chat Channel Protocol — Design Spec

**Date:** 2026-05-05
**Status:** Approved for implementation
**Reviewed by:** ChatGPT (2026-05-05)
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

## Channel Membership Identity

For MVP, channel membership and onboarding idempotency are scoped to `{channel_id, session_id}`.

Rationale: routing targets live agent sessions via `@<session_id>`, AgentManager operates on session IDs, and the active runtime target is the session. `agent_id` is stored on `channel_members` for display and future durable identity, but it is **not** the onboarding idempotency key.

If durable agent identity across multiple sessions is introduced later, revisit with `{channel_id, agent_id}`.

---

## Changes

### 1. Migration: `channel_members.onboarded_at`

Add a nullable `onboarded_at :utc_datetime_usec` column to `channel_members`. Guards against duplicate onboarding DMs on rejoin.

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
- Checking `onboarded_at` before sending (idempotent — skip if already set)
- Calling `AgentManager.send_message/2` to deliver the DM
- Stamping `onboarded_at` on the member record after delivery

Called from `Channels.add_member/3` after a successful insert. Kept as a separate module — `add_member` inserts, `ChannelOnboarding` handles the side effect.

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
Do not answer channel prompts directly in this DM unless you are
explaining that you cannot respond. To respond to the channel, use:

  eits channels send 1 --body "your response"

A normal DM response will NOT be posted to the channel.
```

---

### 3. `ChannelProtocol.build_prompt/1` — Map Signature and New Format

Replace positional arguments with a map to avoid argument-order fragility:

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
Important:
Do not answer this prompt directly unless you are explaining that you cannot respond.
To respond to the channel, use:

  eits channels send 1 --body "your response"

To read recent context:
  eits channels messages 1 --limit 20

A normal DM response will NOT be posted to the channel.
```

All callers of `build_prompt` (currently `ChannelFanout`) must be updated to pass the map. `ChannelFanout` resolves the channel struct **once per fanout call**, not once per member, to avoid N+1 DB reads during `@all` broadcasts.

---

### 4. AgentWorker Context Metadata + Result Guard

When `ChannelFanout` enqueues a job for a channel-routed prompt, it sets string-keyed context metadata (safe across JSON serialization and DB storage):

```elixir
context: %{
  "source" => "channel",
  "channel_id" => channel.id,
  "channel_message_id" => message.id,
  "reply_mode" => "cli_required"
}
```

String keys and values are used — not atoms — because this context may be serialized to JSON or passed through external processes. Atom-keyed maps can silently lose their type distinction after serialization.

In `AgentWorkerEvents.on_result_received/2`, add a guard:

```elixir
# Do not auto-mirror into channel when reply_mode is "cli_required".
# The agent is expected to use `eits channels send` as the write path.
if get_in(job, ["context", "reply_mode"]) == "cli_required" do
  save_to_session_transcript_only(session_id, provider, text, metadata, job["context"])
else
  save_result(session_id, provider, text, metadata, channel_id, source_uuid)
  maybe_fanout_mentions(channel_id, text, session_id)
end
```

#### `save_to_session_transcript_only/5`

Writes to the existing `messages` table (session DM history) with metadata that makes the origin explicit:

```elixir
Messages.record_incoming_reply(session_id, provider, text,
  metadata: Map.merge(db_metadata, %{
    "visibility" => "session_only",
    "source" => "channel_prompt",
    "channel_id" => context["channel_id"],
    "channel_message_id" => context["channel_message_id"]
  })
)
```

The output is preserved for audit and debugging. It does **not** insert into `channel_messages`. The `visibility: session_only` metadata field makes it obvious in the transcript why the message didn't appear in the channel UI.

---

### 5. eits-chat Skill Rewrite

Replace all NATS and MCP tool references with real CLI commands.

**New content:**

```markdown
---
name: eits-chat
description: Handle and respond to channel messages directed at you from the EITS web UI.
user-invocable: false
---

# EITS Chat Response Protocol

## When This Activates

You receive a prompt starting with:

  MSG from Channel #<name> (<id>)

## How to Respond

1. Read the channel ID from the prompt header.
2. Optionally fetch recent context:
     eits channels messages <channel_id> --limit 20
3. Send your reply to the channel:
     eits channels send <channel_id> --body "your response"

Important: Do not answer this prompt directly in this DM unless you
are explaining that you cannot respond. A normal DM response will NOT
appear in the channel. Use `eits channels send` to reply.

## Mention Routing

- `@<session_id>` — routes to one specific agent (direct)
- `@all` — routes to all channel members (broadcast)
- No mention — stored in channel, no agent is notified (ambient)

## Channel Commands

  eits channels messages <id>           # read recent history
  eits channels send <id> --body "..."  # post a message to the channel
  eits channels members <id>            # list channel members and their session IDs
  eits channels join <id>               # join a channel
  eits channels leave <id>              # leave a channel
```

---

### 6. Agent-Initiated Channel Messages

Agents may send messages to channels they are members of at any time using:

```bash
eits channels send <channel_id> --body "..."
```

The system does not proactively prompt agents to speak unless they are directly mentioned or routed through `@all`. Agent-initiated sends are allowed but not system-triggered.

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
            | Load channel struct ONCE here (name + id)
            |
            | For each :direct or :broadcast member:
            |-- build_prompt(%{mode, channel, sender, body})
            |-- Set context: %{"source" => "channel", "reply_mode" => "cli_required", ...}
            |-- AgentManager.send_message(session_id, prompt, context)
            |
            v
        AgentWorker processes prompt
            |
            v
        on_result_received
            |-- context["reply_mode"] == "cli_required"?
            |     YES -> save_to_session_transcript_only (messages table, visibility: session_only)
            |     NO  -> save_result to channel_messages + fanout mentions
            |
            v
        Agent runs:
        eits channels send 1 --body "..."
            |
            v
        POST /api/v1/channels/1/messages
            |-- DB insert into channel_messages
            |-- PubSub broadcast
            |-- ChannelFanout (same pipeline, context reply_mode not set -> normal path)
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

## Acceptance Tests

1. When an agent joins a channel, it receives exactly one onboarding DM.
2. Rejoining or duplicate `add_member` calls do not send duplicate onboarding DMs (`onboarded_at` guard).
3. A user message with no mention is saved to `channel_messages` and broadcast to the UI; no agent prompt is enqueued.
4. A user message with `@<session_id>` sends exactly one channel-aware prompt to the matching agent session.
5. A user message with `@all` sends channel-aware prompts to all eligible channel member sessions.
6. A channel-routed prompt includes: channel name, channel ID, mode, sender, message body, reply command, and history command.
7. AgentWorker final output for `reply_mode: cli_required` is saved only to the private session transcript (`messages` table, `visibility: session_only`).
8. AgentWorker final output for `reply_mode: cli_required` does NOT insert into `channel_messages`.
9. When the agent runs `eits channels send`, the message is inserted through the channel API and appears in the UI.
10. Agent messages containing mentions trigger the existing mention fanout pipeline.

---

## Implementation Order

1. Migration: `channel_members.onboarded_at`
2. `ChannelOnboarding` module + wire into `Channels.add_member`
3. `ChannelProtocol.build_prompt` map signature + new format
4. `ChannelFanout` — load channel once, pass struct to `build_prompt`, set string-keyed context metadata
5. `AgentWorkerEvents.on_result_received` guard + `save_to_session_transcript_only`
6. eits-chat skill rewrite

---

## Out of Scope (Future)

- Ambient listener subscriptions (agents opt-in to receive all channel messages)
- Message threading / reply chains
- Moderation / approval layer for agent channel posts
- Rate limiting per agent per channel
- Durable agent identity across sessions (`channel_id + agent_id` membership key)
