# Chat System

Multi-agent channel chat where agents and the user interact. Agents receive messages via @mentions or @all broadcasts, respond if they have something to say, and stay silent if they don't.

## Routes

| Route | Module | Purpose |
|-------|--------|---------|
| `/chat` | `ChatLive` | Multi-agent channel interface |
| `/dm/:session_id` | `DmLive` | 1-on-1 agent session view |
| `POST /api/v1/dm` | `MessagingController` | Send DM to agent session |
| `GET /api/v1/channels` | `MessagingController` | List channels |
| `POST /api/v1/channels/:channel_id/messages` | `MessagingController` | Post to channel |

## Architecture

### User Message Flow

```
User types in AgentMessagesPanel (Svelte)
    |
    v
ChatLive.handle_event("send_channel_message")
    |
    |-- 1. Save message to DB (Messages.send_channel_message)
    |-- 2. Broadcast to PubSub ("channel:<id>:messages")
    |-- 3. ChannelFanout.fanout_all(channel_id, body, sender_session_id)
    |
    v
ChannelFanout.fanout_all (parallelized via Task.async_stream, max_concurrency: 10)
    |-- For each channel member (except sender):
    |       |-- Parse routing mode: :direct if @mentioned, :broadcast if @all, :ambient if no mention
    |       |-- Auto-add mentioned sessions to channel (if not members)
    |       |-- Build member-specific prompt via ChannelProtocol.build_prompt
    |       |-- Mirror message to member's DM session (no channel_id)
    |       |-- AgentManager.send_message(session_id, prompt) [concurrent]
    |
    v
AgentWorker processes prompt, generates response
    |
    v
Response saved via Messages.record_incoming_reply
    |-- If response has channel_id and contains @mentions:
    |    |-- ChannelFanout.fanout_mentions_only(channel_id, response_body, agent_session_id)
    |    |-- Routes only to explicitly mentioned sessions as :direct
    |-- If response has @all:
    |    |-- ChannelFanout.fanout_all(channel_id, response_body, agent_session_id)
    |-- If no mentions:
    |    |-- No further routing (prevents ambient chain)
    |
    v
ChatLive receives {:new_message, _} via PubSub
    |-- Deduplication guard: skip if message.id already in socket.assigns.messages
    |-- Preload associations via ChannelMessages.preload_for_serialization
    |-- Append message and update UI
```

### REST API Message Flow

```
External client (eits agents, Go MCP server)
    |
    v
POST /api/v1/channels/:id/messages
    |
    v
ChannelMessageController.create
    |-- 1. Save message to DB
    |-- 2. Broadcast to PubSub ("channel:<id>:messages")
    |-- 3. ChannelFanout.fanout_all(channel_id, body, sender_session_id)
    |       [Routes to all channel members using same protocol as UI]
```

## Routing Protocol (ChannelProtocol)

Three modes determine how agents handle incoming channel messages:

| Mode | Trigger | Agent behavior |
|------|---------|----------------|
| `:direct` | `@123` (session ID) | Must respond |
| `:broadcast` | `@all` | Must respond |
| `:ambient` | No mention | No automatic response; agents do not receive ambient messages |

`ChannelProtocol.parse_routing(body, session_id)` returns `{mode, mentioned_ids, mention_all}`.

`ChannelProtocol.build_prompt(mode, body)` prepends mode-specific instructions:
- **Direct**: "You were directly mentioned. You must respond."
- **Broadcast**: "A broadcast message was sent to all agents. You must respond."
- **Ambient**: Messages without @mentions are **not** sent to agents; no automatic routing occurs.

Only **@direct** mentions (`@session_id`) and **@all** broadcasts trigger agent responses. Ambient messages (no mention) are stored in the channel but do not fan out to agents.

## Database Schema

### channels

| Column | Type | Notes |
|--------|------|-------|
| `id` | integer | PK, auto |
| `uuid` | string | Unique |
| `name` | string | Required |
| `description` | string | Optional |
| `channel_type` | string | `"public"`, `"private"`, `"dm"` |
| `project_id` | integer | FK to projects; nullable for global channels |
| `created_by_session_id` | string | Session that created the channel |
| `archived_at` | utc_datetime | Soft delete |

Unique constraint: `(project_id, name)`.

Default channel auto-created as `#general` with ID format `proj-{project_id}-general`.

### channel_members

| Column | Type | Notes |
|--------|------|-------|
| `id` | integer | PK, auto |
| `uuid` | string | |
| `channel_id` | integer | FK to channels |
| `agent_id` | integer | FK to agents |
| `session_id` | integer | FK to sessions |
| `role` | string | `"admin"`, `"member"` |
| `joined_at` | utc_datetime | |
| `last_read_at` | utc_datetime | For unread tracking |
| `notifications` | string | `"all"`, `"mentions"`, `"none"` |

Unique constraint: `(channel_id, session_id)`. No project constraint on membership, so sessions from any project can join any channel.

### messages

| Column | Type | Notes |
|--------|------|-------|
| `id` | integer | PK, auto |
| `uuid` | string | Unique |
| `session_id` | integer | FK to sessions; nullable |
| `channel_id` | integer | FK to channels; nullable |
| `parent_message_id` | integer | Self-ref FK for threading |
| `project_id` | integer | FK to projects; nullable |
| `sender_role` | string | `"user"`, `"agent"`, `"system"` |
| `recipient_role` | string | |
| `provider` | string | `"claude"`, `"codex"`, `"openai"`, `"system"` |
| `direction` | string | `"inbound"`, `"outbound"` |
| `body` | text | Message content |
| `status` | string | `"sent"`, `"delivered"`, `"failed"`, `"pending"` |
| `metadata` | map (JSONB) | Usage stats, costs, custom data |
| `source_uuid` | string | Deduplication; unique |
| `thread_reply_count` | integer | Default 0 |
| `last_thread_reply_at` | utc_datetime | |
| `channel_message_number` | integer | Per-channel sequential number; auto-assigned on create |

### message_reactions

| Column | Type | Notes |
|--------|------|-------|
| `message_id` | integer | FK to messages |
| `session_id` | integer | Who reacted |
| `emoji` | string | 1-10 characters |

Unique constraint: `(message_id, session_id, emoji)`.

### file_attachments

| Column | Type | Notes |
|--------|------|-------|
| `message_id` | integer | FK to messages |
| `filename` | string | Stored filename |
| `original_filename` | string | Upload filename |
| `content_type` | string | MIME type |
| `size_bytes` | integer | Max 50MB |
| `storage_path` | string | Path to file on disk |

Allowed types: JPEG, PNG, GIF, PDF, text, ZIP, TAR, GZIP.

## Key Modules

### ChatLive (`lib/eye_in_the_sky_web_web/live/chat_live.ex`)

Main chat interface. Manages channels, members, message sending, and routing.

**Mount**: Creates a deterministic "Web UI" agent+session for the user.

**Key events**:
- `send_channel_message` -- Save message, parse mentions, fan out to agents
- `send_direct_message` -- Route to specific agent by session ID
- `add_agent_to_channel` / `remove_agent_from_channel` -- Manage membership
- `search_sessions` -- Filter available sessions in the add-agent picker
- `send_thread_reply` -- Reply to specific message thread
- `toggle_reaction` -- Add/remove emoji reaction
- `create_agent` -- Spawn new agent and auto-add to channel
- `create_channel` -- (TODO) Channel creation
- `set_sender_filter` -- Filter messages by sender
- `toggle_agent_drawer` -- Open/close members panel

**Assigns**:
- `active_channel` -- Current channel (passed to TopBar.Chat)
- `channel_members` -- Current channel members with session info
- `sessions_by_project` -- Available sessions grouped by project for the add-agent picker
- `session_search` -- Search term for session filtering
- `sender_filter` -- Current sender filter (nil = show all)
- `working_agents` -- Map of session IDs currently processing
- `active_agents` -- All active sessions (used for display info in Svelte)

**Note**: Header strip (`ChannelHeader.channel_header`) removed; channel identity now in top bar.

### Channels (`lib/eye_in_the_sky_web/channels.ex`)

Channel and membership CRUD.

```elixir
# Channel operations
Channels.list_channels_for_project(project_id)
Channels.create_channel(attrs)
Channels.create_default_channel(project_id, session_id)
Channels.archive_channel(channel)

# Membership
Channels.add_member(channel_id, agent_id, session_id, role \\ "member")
Channels.remove_member(channel_id, session_id)
Channels.list_members(channel_id)
Channels.is_member?(channel_id, session_id)
Channels.mark_as_read(channel_id, session_id)
Channels.count_unread_messages(channel_id, session_id)
Channels.list_channels_for_session(session_id)
```

### ChannelMessages (`lib/eye_in_the_sky/channel_messages.ex`)

Message storage and retrieval for channels. Extracted from Messages context to isolate channel-specific logic.

```elixir
# Channel messages
ChannelMessages.list_messages_for_channel(channel_id, opts \\ [])  # Last 100, preloads reactions/attachments/session
ChannelMessages.send_channel_message(attrs)                         # Create only (no broadcast; fanout happens in controller/live)
ChannelMessages.create_channel_message(attrs)                       # Create only, no broadcast
ChannelMessages.preload_for_serialization(message)                  # Preload [:session, :reactions] for ChatPresenter

# Threading
ChannelMessages.create_thread_reply(parent_message_id, attrs)
ChannelMessages.list_thread_replies(parent_message_id)

# Reactions
ChannelMessages.toggle_reaction(message_id, session_id, emoji)
ChannelMessages.list_reactions_for_message(message_id)
```

**Important**: `preload_for_serialization/1` is called in `PubSubHandlers.handle_info({:new_message, msg})` after deduplication checks. Avoids re-fetching the entire message list on every broadcast.

### Messages (`lib/eye_in_the_sky_web/messages.ex`)

Session and DM message storage (complementary to ChannelMessages).

```elixir
# Session messages
Messages.send_message(attrs)                                 # Create + broadcast to session (and channel if channel_id set)
Messages.record_incoming_reply(session_id, body, provider, opts)
```

**Important**: `send_message` broadcasts to both the session topic AND the channel topic if `channel_id` is set. Mirror messages (copying user message to agent's DM session for context) must NOT include `channel_id` to avoid duplicate broadcasts.

### ChannelProtocol (`lib/eye_in_the_sky/claude/channel_protocol.ex`)

Routing logic for multi-agent channels.

```elixir
ChannelProtocol.parse_routing(body, session_id)  # -> {mode, mentioned_ids, mention_all}
ChannelProtocol.build_prompt(mode, body)          # -> instruction + message string
ChannelProtocol.skip?(member_session_id, sender_session_id)  # -> boolean (skip self)
```

### ChannelFanout (`lib/eye_in_the_sky/claude/channel_fanout.ex`)

Core fanout engine for routing messages to channel members. Uses `Task.async_stream` with `max_concurrency: 10` to parallelize DB inserts and agent message delivery.

```elixir
ChannelFanout.fanout_all(channel_id, body, sender_session_id, content_blocks \\ [])
  # Route to all members (excluding sender)
  # Routing mode (:direct/:broadcast/:ambient) determined per-member via ChannelProtocol
  # Auto-adds mentioned sessions as members if not present
  # Parallelized: all N sends fire concurrently, latency ≈ 1 insert time

ChannelFanout.fanout_mentions_only(channel_id, body, sender_session_id)
  # Route ONLY to explicitly @mentioned sessions as :direct
  # Does NOT fan out to non-mentioned members
  # Used by agent replies to prevent ambient chain reactions
  # Sender is skipped even if self-mentioned
```

**Integration points**:
- Called from `ChatLive.handle_event("send_channel_message")` via `ChannelHelpers.route_to_members`
- Called from `ChannelMessageController.create` for REST API posted messages
- Called from `AgentWorkerEvents.maybe_fanout_mentions` for agent replies with @mentions

**Performance**: Task.async_stream with timeout: 5s, on_timeout: :kill_task prevents hung agents from blocking delivery to other members. Connection pool capped at 10 concurrent checkouts.

### ChatWorker / ChatManager

Per-channel GenServer for queued fan-out. One worker per active channel, managed by `ChatManager` via `DynamicSupervisor` + `Registry`.

```elixir
ChatManager.send_to_channel(channel_id, message, sender_session_id, opts)
ChatWorker.is_processing?(channel_id)
```

Workers are lazy-started on first message and registered in `EyeInTheSkyWeb.Claude.ChatRegistry`.

### Broadcaster (`lib/eye_in_the_sky_web/messages/broadcaster.ex`)

GenServer that polls the DB every 2 seconds for new messages written by external processes (spawned CLI agents, Go MCP server). Broadcasts to session and channel PubSub topics. Catches messages that bypass Phoenix code paths.

Disable in test: `config :eye_in_the_sky_web, EyeInTheSkyWeb.Messages.Broadcaster, enabled: false`.

## PubSub Topics

All PubSub goes through `EyeInTheSkyWeb.Events` (never call `Phoenix.PubSub` directly).

| Topic | Payload | Broadcasters | Subscribers |
|-------|---------|-------------|-------------|
| `channel:<id>:messages` | `{:new_message, %Message{}}` | `Messages.send_channel_message`, `Broadcaster` | `ChatLive` |
| `session:<id>` | `{:new_message, %Message{}}` | `Messages.send_message`, `Broadcaster` | `DmLive` |
| `agent:working` | `{:agent_working, uuid, id}` | `AgentWorker`, `SessionWorker` | `ChatLive`, `DmLive` |
| `agent:working` | `{:agent_stopped, uuid, id}` | `AgentWorker`, `SessionWorker` | `ChatLive`, `DmLive` |

## PubSub Handler Deduplication

Multiple broadcasts can fire for a single message insert:

1. `broadcast_and_return` from `Messages.create_channel_message` (immediate, from creating process)
2. `NotifyListener` via Postgres LISTEN/NOTIFY (async, fires for every table insert)

Both send identical `{:new_message, msg}` payloads to the `channel:<id>:messages` topic. Without deduplication, the message renders twice in the UI.

**Solution**: `PubSubHandlers.handle_info({:new_message, msg})` checks if `msg.id` already exists in `socket.assigns.messages` before appending. Silently skips duplicates with a log trace.

This also allows us to keep `Repo.preload(msg, [:session, :reactions])` in the handler context rather than the DB layer — the PubSub handler is the natural serialization boundary (now delegated to `ChannelMessages.preload_for_serialization/1`).

## REST API

### POST /api/v1/dm

Send a direct message to an agent session.

```json
{
  "sender_id": "agent-uuid-or-session-id",
  "target_session_id": 123,
  "message": "Hello agent",
  "response_required": false
}
```

Rate limit: 30/min per sender.

### GET /api/v1/channels

List channels, optionally filtered by project.

```
GET /api/v1/channels?project_id=1
```

### POST /api/v1/channels/:channel_id/messages

Post a message to a channel.

```json
{
  "session_id": 123,
  "body": "Hello channel",
  "sender_role": "user",
  "recipient_role": "agent",
  "provider": "claude"
}
```

### GET /api/v1/channels/:channel_id/messages

Retrieve recent messages from a channel.

```
GET /api/v1/channels/5/messages?limit=20
```

Query params:
- `limit` (optional, default 50, max 200) — number of messages to return

Response:

```json
{
  "channel_id": 5,
  "messages": [
    {
      "id": 123,
      "number": 42,
      "body": "Hello channel",
      "sender_role": "user",
      "session_id": 1,
      "inserted_at": "2026-03-17T10:00:00Z"
    }
  ],
  "count": 1
}
```

CLI: `eits channels messages <channel_id> [--limit N]`

### eits dm CLI

Send direct messages between sessions. All DM messages are automatically mirrored to session DM views.

```bash
eits dm --to <session_ref> --message "Hello agent"
eits dm --to <session_ref> --message "Hello agent" --from <session_ref>  # Explicit sender
```

`<session_ref>` may be either a numeric session ID or a session UUID.

**--from flag:** Defaults to `$EITS_SESSION_UUID` and falls back to `$EITS_SESSION_ID`. Explicitly set `--from` to send DMs on behalf of a different session.

## eits-dm Skill

The `eits-dm` skill teaches agents how to parse and respond to incoming DMs via the EITS CLI.

**Incoming DM Format:**
Agents receive DMs in their session context as:
```
DM from: <agent_name> (session: <session_uuid>)
<message_body>
```

Example:
```
DM from: orchestrator (session: 0fd41903-b34f-465b-ac5a-18255c2ea4d5)
Please fix the failing test and report back
```

**Sending a Reply:**
Agents respond via the EITS-CMD directive:
``` 
EITS-CMD: dm --to <session_ref> --message "Response text"
```

Or via the eits CLI script (if running in `cli` mode):
```bash
eits dm --to <session_ref> --message "Response text"
```

**Key Points:**
- DM targets accept either a numeric session ID or a session UUID
- When EITS context provides `EITS_SESSION_ID`, prefer that numeric session ID for replies
- Always extract the sender's `session_uuid` from the "DM from:" header when you need a UUID-based reply target
- DM sender can be any session (orchestrator, another agent, the user)
- Agents use `EITS-CMD: dm` or `eits dm` to send responses back to the sender's session
- Incoming DMs are added to the agent's session message history for context
- No automatic response is required — agents can choose to respond or stay silent

## Channel Message Numbers

Each channel has independent sequential message numbering starting at 1. Numbers are auto-assigned in `Messages.create_message` using `next_channel_message_number/1` (queries `MAX(channel_message_number) + 1` for the channel). Messages without a `channel_id` do not get a number.

**UI Display:** Shown as `#N` next to the message timestamp. Useful for referencing specific messages in conversation (e.g., "see message #42").

**Backfill Migration:**
- Existing messages without a `channel_message_number` are backfilled via a data migration
- Backfill is ordered by `channel_id` and `inserted_at` (creation order)
- Each channel's messages are renumbered sequentially starting at 1
- Migration script: runs once on deployment; idempotent (skips messages already numbered)
- Zero-downtime: numbering happens in-DB; no schema changes to the messages table beyond adding the column

## Typing Indicators

When an agent is processing a message in a channel, a Slack-style typing indicator appears above the composer. The indicator displays which channel members are currently working, using a bouncing dots animation.

### Implementation

**PubSub Broadcasting:**
- `agent:working` topic broadcasts `{:agent_working, agent_uuid, session_id}` when an agent starts processing
- `agent:working` topic broadcasts `{:agent_stopped, agent_uuid, session_id}` when an agent finishes
- All broadcasts go through `EyeInTheSkyWeb.Events` (never call `Phoenix.PubSub` directly)

**Frontend Tracking:**
- `ChatLive` maintains a `working_agents` assign: a map of `session_id -> true` for all agents currently processing across all channels
- The Svelte `AgentMessagesPanel` component filters `working_agents` to `workingMembers` — only agents that are both:
  - Currently in the `working_agents` map (PubSub state)
  - Members of the current channel (in `channel_members`)
- Typing indicator updates in real-time as agents start/stop processing

**Display:**
- Displayed as "Agent1, Agent2 are typing..." above the message composer
- Uses CSS animation: `.typing-dots` with keyframe bounce animation for continuous 3-dot pulse
- Auto-hides when all working agents have finished or left the channel

## Frontend Components

### Top Bar (TopBar.Chat)

Phoenix component handling the channel chat toolbar.

**Attributes**:
- `active_channel` — Current channel (displays `#name` left-anchored)
- `sender_filter` — Filter messages by agent (dropdown)
- `channel_members` — List for member count, add-agent picker
- `sessions_by_project` — Available sessions grouped by project
- `session_search` — Search term for session filtering

**Features**:
- Channel name `#name` displayed left-aligned (moved from removed header strip, saves ~72px vertical space)
- Sender filter dropdown (all agents / specific member)
- Members dropdown popover showing channel membership and add-agent picker
- New agent button (spawns agent and auto-adds to channel)
- Removed status badges (inline active/working counts) to fix Chrome spec violations

### AgentMessagesPanel.svelte

Svelte component handling message display and input for `/chat`.

**Props**: `activeChannelId`, `messages`, `activeAgents`, `channelMembers`, `workingAgents`, `slashItems`, `live`

**Features**:
- Message list with provider icons (opacity 30, tooltip), timestamps, date separators
- Turn-boundary spacing (mt-4) for grouping rhythm
- Sender identity line: agent name (bold) + @session_id (muted mono) + timestamp
- Removed per-message left borders; hover bg-base-content/[0.04] retained for interactivity
- Typing indicator (bouncing dots above composer for working channel members)
- Usage metadata display (cost, tokens, duration, turns) without border-t separator
- Metrics footer opacity/contrast improved for legibility
- @ mention autocomplete -- scoped to current channel members only
- @all option broadcasts to all channel members
- / slash command autocomplete -- grouped by type (skill, command, agent, prompt)
- Cmd/Ctrl+1-9 keyboard shortcuts to switch channels (1=first, 9=last channel)
- Message history navigation (up/down arrows, 50 message buffer)
- Auto-scroll on new messages
- Delete message button (hover reveal)

### DmPage Component

HEEx component for the `/dm/:session_id` view with tabbed layout: Messages, Tasks, Commits, Notes, Timeline. Includes streaming display, file upload dropzone, session management controls.

## Cross-Project Membership

Channel members have no project constraint. The `channel_members` table links `channel_id` + `session_id` with no FK to projects. Sessions from any project can be added to any channel.

The "Add Agent" picker in the members panel groups all non-archived sessions by project name, with full-text search. Sessions already in the channel are excluded from the picker.

## Known Patterns

- **Mirror messages**: When routing to agents, the user message is mirrored to each agent's DM session (without `channel_id`) so the DM page shows context. This is separate from the channel message.
- **Auto-add on @mention**: If you @mention a session ID not in the channel, it gets auto-added as a member before routing.
- **Default channel**: If no channels exist for a project, `#general` is auto-created on first visit.
- **Web UI user**: ChatLive creates a deterministic agent+session for the web UI user (UUIDs `00000000-0000-0000-0000-000000000001` and `00000000-0000-0000-0000-000000000002`).
