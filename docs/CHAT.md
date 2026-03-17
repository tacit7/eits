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

```
User types in AgentMessagesPanel (Svelte)
    |
    v
ChatLive.handle_event("send_channel_message")
    |
    |-- 1. Save message to DB (Messages.send_channel_message)
    |-- 2. Broadcast to PubSub ("channel:<id>:messages")
    |-- 3. Parse @mentions (ChannelProtocol.parse_routing)
    |-- 4. Auto-add mentioned sessions to channel
    |-- 5. For each channel member (except sender):
    |       |-- Determine routing mode (direct/broadcast/ambient)
    |       |-- Build member-specific prompt
    |       |-- Mirror message to member's DM session (no channel_id)
    |       |-- AgentManager.send_message(session_id, prompt)
    |
    v
AgentWorker processes prompt, generates response
    |
    v
Response saved via Messages.record_incoming_reply
    |-- Broadcast to session topic + channel topic
    |
    v
ChatLive receives {:new_message, _} -> reloads from DB
```

## Routing Protocol (ChannelProtocol)

Three modes determine how agents handle incoming channel messages:

| Mode | Trigger | Agent behavior |
|------|---------|----------------|
| `:direct` | `@123` (session ID) | Must respond |
| `:broadcast` | `@all` | Must respond |
| `:ambient` | No mention | Message delivered but no response requested |

`ChannelProtocol.parse_routing(body, session_id)` returns `{mode, mentioned_ids, mention_all}`.

`ChannelProtocol.build_prompt(mode, body)` prepends mode-specific instructions:
- **Direct**: "You were directly mentioned. You must respond."
- **Broadcast**: "A broadcast message was sent to all agents. You must respond."
- **Ambient**: No prompt sent; message is delivered to the agent's DM session as context only. `AgentManager.send_message` is NOT called for ambient messages.

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

**Assigns**:
- `channel_members` -- Current channel members with session info
- `sessions_by_project` -- Available sessions grouped by project for the add-agent picker
- `session_search` -- Search term for session filtering
- `working_agents` -- Map of session IDs currently processing
- `active_agents` -- All active sessions (used for display info in Svelte)

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

### Messages (`lib/eye_in_the_sky_web/messages.ex`)

Message storage and retrieval.

```elixir
# Channel messages
Messages.list_messages_for_channel(channel_id, opts \\ [])  # Last 100, preloads reactions/attachments/session
Messages.send_channel_message(attrs)                         # Create + broadcast to channel
Messages.create_channel_message(attrs)                       # Create only, no broadcast

# Session messages
Messages.send_message(attrs)                                 # Create + broadcast to session (and channel if channel_id set)
Messages.record_incoming_reply(session_id, body, provider, opts)

# Threading
Messages.create_thread_reply(parent_message_id, attrs)
Messages.list_thread_replies(parent_message_id)

# Reactions
Messages.toggle_reaction(message_id, session_id, emoji)
Messages.list_reactions_for_message(message_id)
```

**Important**: `send_message` broadcasts to both the session topic AND the channel topic if `channel_id` is set. Mirror messages (copying user message to agent's DM session for context) must NOT include `channel_id` to avoid duplicate broadcasts.

### ChannelProtocol (`lib/eye_in_the_sky_web/claude/channel_protocol.ex`)

Routing logic for multi-agent channels.

```elixir
ChannelProtocol.parse_routing(body, session_id)  # -> {mode, mentioned_ids, mention_all}
ChannelProtocol.build_prompt(mode, body)          # -> instruction + message string
ChannelProtocol.skip?(member_session_id, sender_session_id)  # -> boolean (skip self)
```

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

## Channel Message Numbers

Each channel has independent sequential message numbering. Numbers are auto-assigned in `Messages.create_message` using `next_channel_message_number/1` (MAX + 1 query). Messages without a `channel_id` do not get a number.

Displayed in the UI as `#N` next to the timestamp. Useful for referencing specific messages in conversation (e.g., "see message #42").

## Typing Indicator

When an agent is processing a message, a Slack-style typing indicator appears above the composer. The indicator shows which channel members are currently working, using bouncing dots animation.

Source: `agent:working` PubSub topic. `ChatLive` tracks `working_agents` assign (map of session_id -> true). The Svelte component filters this to `workingMembers` — only agents that are both working AND members of the current channel.

## Frontend Components

### AgentMessagesPanel.svelte

Svelte component handling message display and input for `/chat`.

**Props**: `activeChannelId`, `messages`, `activeAgents`, `channelMembers`, `workingAgents`, `slashItems`, `live`

**Features**:
- Message list with provider icons, timestamps, date separators
- Typing indicator (bouncing dots above composer for working channel members)
- Usage metadata display (cost, tokens, duration, turns)
- @ mention autocomplete -- scoped to current channel members only
- @all option broadcasts to all channel members
- / slash command autocomplete -- grouped by type (skill, command, agent, prompt)
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
