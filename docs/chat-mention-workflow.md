# Eye in the Sky: @mention Workflow

## Overview

The @mention system in Eye in the Sky (EITS) allows users to interact with Claude agents through a chat interface. When a user types `@<session_id>` followed by a message, the system routes that message to the appropriate agent session and spawns a Claude process to handle the request.

## Architecture Components

### 1. Frontend (Svelte)
- **File**: `assets/svelte/components/tabs/AgentMessagesPanel.svelte`
- **Responsibility**: Capture user input, detect @mentions, trigger LiveView events

### 2. Phoenix LiveView
- **File**: `lib/eye_in_the_sky_web_web/live/chat_live.ex`
- **Responsibility**: Handle UI events, manage WebSocket state, coordinate backend actions

### 3. Session Worker
- **File**: `lib/eye_in_the_sky_web/claude/session_worker.ex`
- **Responsibility**: Manage individual Claude CLI subprocess, parse output, record messages

### 4. JetStream Consumer
- **File**: `lib/eye_in_the_sky_web/nats/jetstream_consumer.ex`
- **Responsibility**: Listen for NATS messages, broadcast to Phoenix PubSub for LiveView updates

### 5. Messages Context
- **File**: `lib/eye_in_the_sky_web/messages.ex`
- **Responsibility**: Store messages in SQLite, manage metadata, handle deduplication

## Complete Message Flow

### Step 1: User Types @mention in Chat UI

**Location**: Svelte component
```svelte
<input
  type="text"
  bind:value={inputValue}
  on:input={handleInputChange}
  placeholder="Send instruction to agents (use @id for direct messages)..."
/>
```

When user types `@42 hello`, the `handleInputChange` function:
1. Detects the `@` character
2. Extracts the session ID (`42`)
3. Shows autocomplete dropdown with matching active agents
4. User selects or finishes typing

### Step 2: Submit Triggers Direct Message Event

**Location**: Svelte component
```javascript
function handleSubmit() {
  const match = inputValue.match(/^@(\d+)\s+(.+)/)
  if (match) {
    const sessionId = match[1]
    const body = match[2]
    live.pushEvent('send_direct_message', {
      session_id: sessionId,
      body: body,
      channel_id: activeChannelId
    })
  }
}
```

### Step 3: LiveView Handles Direct Message Event

**Location**: `chat_live.ex`
```elixir
def handle_event("send_direct_message", %{"session_id" => target_session_id, "body" => body, "channel_id" => channel_id}, socket) do
  # 1. Parse session_id to integer
  target_id = parse_session_id(target_session_id)

  # 2. Create message in database
  {:ok, message} = Messages.send_channel_message(%{
    channel_id: channel_id,
    session_id: user_session_id,
    sender_role: "user",
    recipient_role: "agent",
    provider: "claude",
    body: body
  })

  # 3. Broadcast to PubSub for UI update
  Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "channel:#{channel_id}:messages", {:new_message, message})

  # 4. Resume target agent's Claude session
  {:ok, session} = Sessions.get_session(target_id)
  {:ok, agent} = Agents.get_agent(session.agent_id)

  prompt_with_reminder = "eits-chat: channel:#{channel_id} seq:#{latest_seq} msg:#{body}"

  EyeInTheSkyWeb.Claude.SessionManager.resume_session(
    session.uuid,
    prompt_with_reminder,
    model: "sonnet",
    project_path: agent.git_worktree_path
  )
end
```

### Step 4: SessionManager Spawns SessionWorker

**Location**: `lib/eye_in_the_sky_web/claude/session_manager.ex`
```elixir
def resume_session(session_id, prompt, opts) do
  session_ref = make_ref()

  worker_spec = %{
    spawn_type: :resume,
    session_id: session_id,
    prompt: prompt,
    opts: Keyword.put(opts, :session_ref, session_ref)
  }

  # Start SessionWorker under DynamicSupervisor
  DynamicSupervisor.start_child(SessionSupervisor, {SessionWorker, worker_spec})
end
```

### Step 5: SessionWorker Broadcasts Working State

**Location**: `session_worker.ex` `init/1`
```elixir
def init(%{spawn_type: spawn_type, session_id: session_id, prompt: prompt, opts: opts}) do
  # Resolve integer PK for FK references
  session_int_id = resolve_session_int_id(session_id)

  # Spawn Claude CLI process
  {:ok, port, session_ref} = spawn_cli(spawn_type, session_id, prompt, opts)

  # Broadcast agent working state
  Phoenix.PubSub.broadcast(
    EyeInTheSkyWeb.PubSub,
    "agent:working",
    {:agent_working, session_id, session_int_id}
  )

  {:ok, %{session_ref: session_ref, session_id: session_id, session_int_id: session_int_id, port: port}}
end
```

### Step 6: Claude CLI Processes Request

**Location**: `lib/eye_in_the_sky_web/claude/cli.ex`
```bash
# Spawned command
/usr/bin/script -q /dev/null /path/to/claude \
  --resume <session_uuid> \
  -p "eits-chat: channel:1 seq:1847 msg:@40 hello" \
  --model sonnet \
  --output-format json \
  --verbose \
  --dangerously-skip-permissions
```

Claude processes the request and outputs JSON:
```json
{
  "type": "result",
  "subtype": "success",
  "is_error": false,
  "duration_ms": 1307,
  "duration_api_ms": 1288,
  "num_turns": 1,
  "result": "Hello! How can I help you?",
  "session_id": "2f9e46c1-e6e1-4d5e-b745-c58dee8028a1",
  "total_cost_usd": 0.05775175,
  "usage": {
    "input_tokens": 3,
    "cache_creation_input_tokens": 46151,
    "output_tokens": 12
  },
  "uuid": "dc9d8cf4-8668-44a5-b45f-c6601e00ff41"
}
```

### Step 7: SessionWorker Parses JSON Output

**Location**: `session_worker.ex` `handle_info/2`
```elixir
def handle_info({:claude_output, _ref, line}, state) do
  case Jason.decode(line) do
    {:ok, parsed} -> handle_parsed_output(parsed, state)
    {:error, _} -> {:noreply, state}
  end
end

defp handle_parsed_output(%{"type" => "result", "result" => content} = parsed, state) do
  # Extract usage metadata
  metadata = %{
    duration_ms: parsed["duration_ms"],
    total_cost_usd: parsed["total_cost_usd"],
    usage: parsed["usage"],
    model_usage: parsed["modelUsage"]
  }

  # Record message with metadata
  Messages.record_incoming_reply(
    state.session_int_id,
    "claude",
    content,
    source_uuid: parsed["uuid"],
    metadata: metadata
  )
end
```

### Step 8: Message Stored in Database

**Location**: `messages.ex`
```elixir
def record_incoming_reply(session_id, provider, body, opts) do
  metadata = Keyword.get(opts, :metadata, %{})
  source_uuid = Keyword.get(opts, :source_uuid)

  attrs = %{
    id: Ecto.UUID.generate(),
    session_id: session_id,
    sender_role: "agent",
    recipient_role: "user",
    provider: provider,
    direction: "inbound",
    body: body,
    status: "delivered",
    source_uuid: source_uuid,
    metadata: metadata  # Stored as JSONB
  }

  create_message(attrs)
end
```

### Step 9: NATS Publisher Publishes Message

**Location**: `lib/eye_in_the_sky_web/nats/publisher.ex`
```elixir
def publish_message(message) do
  envelope = %{
    op: "msg",
    channel: "chat",
    version: "eits-messaging-v2",
    channel_id: message.channel_id,
    msg: message.body,
    meta: %{
      message_id: message.id,
      sender_session_id: message.session_id,
      provider: message.provider
    }
  }

  Gnat.pub(:gnat, "events.channel.#{message.channel_id}", Jason.encode!(envelope))
end
```

### Step 10: JetStream Consumer Receives and Broadcasts

**Location**: `jetstream_consumer.ex`
```elixir
def handle_message(nats_message, state) do
  decoded = decode_body(nats_message.body)

  # Broadcast to NATS page UI
  Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "nats:events", {:nats_message, topic, decoded})

  # Process based on message type
  case decoded do
    %{"op" => "msg", "channel" => "chat", "version" => "eits-messaging-v2"} ->
      handle_v2_channel_message(decoded)
  end

  {:ack, state}
end

defp handle_v2_channel_message(envelope) do
  message_id = get_in(envelope, ["meta", "message_id"])
  channel_id = envelope["channel_id"]

  case Messages.get_message(message_id) do
    {:ok, message} ->
      # Broadcast to LiveView subscribers
      Phoenix.PubSub.broadcast(
        EyeInTheSkyWeb.PubSub,
        "channel:#{channel_id}:messages",
        {:new_message, message}
      )
  end
end
```

### Step 11: ChatLive Receives PubSub Broadcast

**Location**: `chat_live.ex` `handle_info/2`
```elixir
def handle_info({:new_message, _message}, socket) do
  # Reload messages from database
  messages =
    Messages.list_messages_for_channel(socket.assigns.active_channel_id)
    |> serialize_messages()

  # Update socket assigns (triggers LiveView push to client)
  {:noreply, assign(socket, :messages, messages)}
end

defp serialize_message(message) do
  %{
    id: message.id,
    session_id: message.session_id,
    sender_role: message.sender_role,
    body: message.body,
    provider: message.provider,
    inserted_at: message.inserted_at,
    metadata: message.metadata || %{}  # Includes cost, tokens, duration
  }
end
```

### Step 12: Svelte Component Updates UI

**Location**: `AgentMessagesPanel.svelte`
```svelte
{#each messages as message}
  <div class="message">
    <p>{message.body}</p>

    <!-- Usage metadata for agent messages -->
    {#if message.sender_role === 'agent' && message.metadata?.total_cost_usd}
      <div class="metadata">
        <span>${message.metadata.total_cost_usd.toFixed(4)}</span>
        <span>{message.metadata.usage.input_tokens} in</span>
        <span>{message.metadata.usage.output_tokens} out</span>
        <span>{(message.metadata.duration_ms / 1000).toFixed(1)}s</span>
      </div>
    {/if}
  </div>
{/each}
```

### Step 13: SessionWorker Terminates and Broadcasts Stop

**Location**: `session_worker.ex` `terminate/2`
```elixir
def terminate(_reason, state) do
  # Broadcast agent stopped state
  Phoenix.PubSub.broadcast(
    EyeInTheSkyWeb.PubSub,
    "agent:working",
    {:agent_stopped, state.session_id, state.session_int_id}
  )

  :ok
end
```

## Message Format: eits-chat Protocol

When an agent is resumed via @mention, the prompt follows this format:

```
eits-chat: channel:{channel_id} seq:{nats_sequence} msg:{user_message}
```

Example:
```
eits-chat: channel:1 seq:1847 msg:@40 create a doc on the workflow
```

This format is parsed by the `eits-chat` skill (located at `~/.claude/skills/eits-chat/SKILL.md`), which instructs the agent on how to respond:

1. Acknowledge receipt via `i-chat-send`
2. Perform the requested work
3. Use `i-chat-send` to ask questions or provide updates
4. Report completion via `i-chat-send`

## Database Schema

### messages table
```sql
CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  uuid TEXT NOT NULL UNIQUE,
  session_id INTEGER,  -- FK to sessions.id (integer PK)
  channel_id INTEGER,  -- FK to channels.id
  sender_role TEXT NOT NULL,  -- "user" or "agent"
  recipient_role TEXT,
  provider TEXT,  -- "claude", "system", etc.
  direction TEXT NOT NULL,  -- "inbound" or "outbound"
  body TEXT NOT NULL,
  status TEXT DEFAULT 'sent' NOT NULL,
  metadata TEXT DEFAULT '{}',  -- JSONB with cost, tokens, duration
  source_uuid TEXT,  -- Deduplication key from Claude CLI
  inserted_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  FOREIGN KEY (channel_id) REFERENCES channels(id) ON DELETE CASCADE
);
```

## Phoenix PubSub Topics

### Global Topics
- `"agent:working"` - Agent working state changes (start/stop)
  - Messages: `{:agent_working, session_uuid, session_int_id}`, `{:agent_stopped, session_uuid, session_int_id}`

### Channel-Specific Topics
- `"channel:#{channel_id}:messages"` - New messages in channel
  - Messages: `{:new_message, message}`

### Session-Specific Topics
- `"session:#{session_id}"` - Session lifecycle events
  - Messages: `{:claude_complete, session_ref, exit_code}`, `{:claude_response, session_ref, parsed_output}`

### NATS Debug Topic
- `"nats:events"` - All NATS messages for debugging
  - Messages: `{:nats_message, subject, decoded_payload}`

## Key Design Decisions

### 1. Dual Message Path
- **User messages**: Created by LiveView, published to NATS, consumed by JetStream
- **Agent messages**: Created by SessionWorker, published to NATS, consumed by JetStream
- **Why**: Decouples UI from agent processing, allows multiple consumers, provides audit trail

### 2. Integer vs UUID Session IDs
- Database uses integer PKs for foreign keys (`session_id`)
- Registry/PubSub uses UUIDs for process identification (`session_uuid`)
- SessionWorker stores both: `session_id` (UUID), `session_int_id` (integer)
- **Why**: Integer PKs are efficient for DB joins, UUIDs are stable across processes/machines

### 3. JSON Output Format
- Changed from `--output-format stream-json` to `--output-format json`
- Provides structured result with usage metadata in single payload
- **Why**: Easier to parse, includes cost/token/duration data, no streaming complexity

### 4. Metadata Storage
- Stored in `messages.metadata` column as JSONB
- Includes: `total_cost_usd`, `duration_ms`, `usage` (tokens), `model_usage`
- **Why**: Allows rich UI display without schema changes, flexible for future additions

### 5. Working Indicator
- SessionWorker broadcasts working state on init and terminate
- ChatLive subscribes globally to `"agent:working"` topic
- **Why**: Real-time feedback, works across multiple LiveView connections, minimal overhead

## Troubleshooting

### Messages Not Showing in UI
1. Check Phoenix logs for `"📨 Received new_message broadcast"`
2. Verify JetStream consumer is running (look for `"JetStreamConsumer: starting pull consumer"`)
3. Check NATS connection: `ps aux | grep nats-server`
4. Verify message was published: Phoenix logs should show `"Published channel message"`

### Working Indicator Not Appearing
1. Check Phoenix logs for `"📢 Broadcasting agent_working"`
2. Check ChatLive logs for `"🔔 ChatLive received agent_working"`
3. Check browser console for `"🔍 workingAgents updated"`
4. Verify ChatLive mount subscription: `Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")`

### Metadata Not Displaying
1. Check SessionWorker logs for `"Result message detected"` with cost info
2. Query database: `SELECT metadata FROM messages WHERE sender_role = 'agent' ORDER BY id DESC LIMIT 1`
3. Verify Svelte component has `message.metadata?.total_cost_usd` check
4. Ensure `--output-format json` is being used (not `stream-json`)

### Agent Not Responding to @mention
1. Check if session exists: `SELECT * FROM sessions WHERE id = <session_id>`
2. Verify SessionManager spawned worker: logs should show `"SessionWorker started for"`
3. Check Claude CLI output for errors
4. Verify `eits-chat` skill exists at `~/.claude/skills/eits-chat/SKILL.md`

## Related Files

### Backend (Elixir/Phoenix)
- `lib/eye_in_the_sky_web/claude/cli.ex` - Claude CLI spawning
- `lib/eye_in_the_sky_web/claude/session_manager.ex` - SessionWorker lifecycle
- `lib/eye_in_the_sky_web/claude/session_worker.ex` - Individual session management
- `lib/eye_in_the_sky_web/messages.ex` - Message storage and queries
- `lib/eye_in_the_sky_web/nats/publisher.ex` - NATS message publishing
- `lib/eye_in_the_sky_web/nats/jetstream_consumer.ex` - NATS message consumption
- `lib/eye_in_the_sky_web_web/live/chat_live.ex` - LiveView chat UI

### Frontend (Svelte)
- `assets/svelte/components/tabs/AgentMessagesPanel.svelte` - Chat interface

### Skills
- `~/.claude/skills/eits-chat/SKILL.md` - Agent chat response protocol

### Configuration
- `config/dev.exs` - Development config (NATS, SQLite)
- `config/runtime.exs` - Production config

## Testing the Flow

### 1. Start NATS Server
```bash
nats-server -js
```

### 2. Start Phoenix Server
```bash
cd /Users/urielmaldonado/projects/eits/web
mix phx.server
```

### 3. Open Chat UI
```
http://localhost:4000/chat
```

### 4. Find Active Agent
```sql
sqlite3 ~/.config/eye-in-the-sky/eits.db "SELECT id, uuid, name FROM sessions WHERE status = 'active' LIMIT 5"
```

### 5. Send @mention
In chat input:
```
@40 hello world
```

### 6. Watch Logs
Phoenix terminal should show:
```
[info] 📢 Broadcasting agent_working for session_id=<uuid>, session_int_id=40
[info] SessionWorker started for <uuid> (ref: #Reference<...>)
[info] Parsed Claude output: %{"type" => "result", "result" => "...", ...}
[info] Result message detected - uuid: <uuid>, cost: $0.0578
[info] 📨 Received new_message broadcast for channel 1
[info] 📬 Loaded 125 messages from DB
[info] 🛑 ChatLive received agent_stopped for session_int_id=40
```

### 7. Verify Message in UI
The agent's response should appear with metadata below it:
```
$0.0578 • 3 in • 12 out • 1.3s • 1 turns
```
