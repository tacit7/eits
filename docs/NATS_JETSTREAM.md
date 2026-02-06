# NATS JetStream Durable Pull Consumer Architecture

The Eye in the Sky web application uses NATS JetStream for reliable message delivery between Claude Code agents and the Phoenix backend. The messaging system is split into two OTP processes with distinct responsibilities.

## Architecture Overview

```
NATS Server (localhost:4222)
    |
    +--- pub/sub: events.> ---------> Consumer (GenServer)
    |                                    |
    |                                    v
    |                               Phoenix PubSub "nats:events"
    |                                    |
    |                                    v
    |                               NATS Viewer UI (LiveView)
    |
    +--- JetStream: EVENTS stream --> JetStreamConsumer (PullConsumer)
                                         |
                                         v
                                    Business Logic
                                    (Messages DB, DM delivery, dedup)
```

## Process 1: `EyeInTheSkyWeb.NATS.Consumer` (GenServer)

**File:** `lib/eye_in_the_sky_web/nats/consumer.ex`

Responsibilities:
- Starts a `Gnat` connection to `localhost:4222`
- Registers the connection process as `:gnat` (used by all other NATS code)
- Subscribes to `events.>` via standard NATS pub/sub
- Relays all messages to Phoenix PubSub topic `"nats:events"` for the NATS viewer UI
- Attempts JSON decode; broadcasts raw body if decode fails

This process contains NO business logic. It is purely a connection manager and pub/sub relay for the UI.

## Process 2: `EyeInTheSkyWeb.NATS.JetStreamConsumer` (PullConsumer)

**File:** `lib/eye_in_the_sky_web/nats/jetstream_consumer.ex`

Uses the `Gnat.Jetstream.PullConsumer` behavior from Gnat 1.12.1.

Configuration:
- Stream: `"EVENTS"`
- Durable consumer name: `"eits-web"`
- Filter subject: `"events.>"`
- Deliver policy: `:new` (only future messages on first creation)
- Ack policy: `:explicit`

Startup sequence:
1. `wait_for_gnat/1` polls for the `:gnat` registered process (up to 10 retries, 500ms apart)
2. `ensure_consumer_exists/0` checks if the durable consumer exists via `Gnat.Jetstream.API.Consumer.info/3`; creates it if missing
3. Starts the pull consumer with `connection_name: :gnat`

On subsequent restarts, the NATS server tracks the last acknowledged sequence number. No replay of old messages occurs.

## Publisher: `EyeInTheSkyWeb.NATS.Publisher`

**File:** `lib/eye_in_the_sky_web/nats/publisher.ex`

Outbound publishing module used by the Phoenix app to send messages to NATS. Supports three protocols:

| Function | Protocol | Subject | Use Case |
|----------|----------|---------|----------|
| `publish_message/2` | eits-messaging-v1 | `events.chat` | Session-based user messages |
| `publish_channel_message/3` | eits-messaging-v2 | `events.channel.{channel_id}` | Multi-agent channel messages |
| `publish_direct_message/3` | eits-messaging-v3 | `events.direct.{session_id}` | Direct messages to specific agents |
| `broadcast_message/2` | eits-messaging-v1 | `events.protocol` | Broadcast to all agents |

All publish functions look up `:gnat` via `Process.whereis/1`.

## Supervision Tree Order

Defined in `lib/eye_in_the_sky_web/application.ex`, strategy `:one_for_one`:

1. `EyeInTheSkyWeb.NATS.Consumer` -- starts first, registers `:gnat`
2. `EyeInTheSkyWeb.NATS.JetStreamConsumer` -- starts second, depends on `:gnat`

The JetStreamConsumer will retry up to 10 times (5 seconds total) waiting for `:gnat` to appear.

## Message Routing

The JetStreamConsumer routes messages based on envelope structure:

| Envelope Pattern | Handler | Description |
|-----------------|---------|-------------|
| `op: "msg", channel: "chat", version: "eits-messaging-v2"` | `handle_v2_channel_message/1` | V2 channel messages with `channel_id` |
| `op: "msg", channel: "chat"` | `handle_v1_session_message/1` | V1 session-based messages (backward compat) |
| `op: "ack"` | (logged only) | Acknowledgment messages |
| Any other with `receiver_id` present | `maybe_handle_dm/2` | Direct messages to sessions |

### V2 Channel Messages

Extracts `channel_id`, `parent_message_id`, and metadata from the envelope. Inserts into the messages table and broadcasts to `"channel:#{channel_id}:messages"` via Phoenix PubSub.

### V1 Session Messages

Uses `reply_to` field as the session ID. Calls `Messages.record_incoming_reply/3` and broadcasts to `"session:#{session_id}:messages"`.

### Direct Messages

Looks for `receiver_id` in multiple envelope locations (`receiver_id`, `receiver`, `receiverId`, or `meta.receiver_id`). Inserts with a dedup ID and broadcasts to `"session:#{session_id}"` topic with `{:nats_message_for_agent, message_text}`.

## Deduplication Strategy

Three-layer dedup prevents duplicate database records:

### Layer 1: Explicit Message ID
If the envelope contains `meta.message_id`, `message_id`, or `id`, that value is used directly as the database primary key.

### Layer 2: SHA256 Hash
If no explicit ID is present, compute a deterministic ID:
```
SHA256("sender_id:receiver_id:body") |> Base.encode16(lowercase) |> truncate to 36 chars
```

### Layer 3: Pre-Insert Check
`Messages.message_exists?(dedup_id)` is called before every insert. If the ID already exists, the message is skipped.

### Layer 4: PK Constraint
The database primary key constraint acts as the final safety net if a race condition bypasses the pre-insert check.

## Body Decoding

Messages may arrive base64-encoded or as raw JSON. The decoder tries two strategies in order:

1. Base64 decode the body, then JSON parse the decoded bytes
2. If base64 decode fails (`:error`), try JSON parsing the raw body directly

This handles both MCP tool payloads (which base64-encode) and direct NATS publishes (raw JSON).

## Previous Architecture

Before the JetStreamConsumer was introduced, the old `NATS.Consumer` had a manual JetStream polling loop:

- Stored `last_sequence` in GenServer state (reset to 0 on every restart)
- Polled `$JS.API.STREAM.INFO.EVENTS` every 2 seconds
- Fetched messages by sequence number via `$JS.API.STREAM.MSG.GET.EVENTS`
- Processed messages through BOTH pub/sub AND JetStream paths (double processing)
- `broadcast_to_dm` had no dedup, creating duplicate DB records on every restart

The new architecture eliminates all of these problems by letting the NATS server track consumer position.

## Operational Notes

### Inspect Consumer State
```bash
nats consumer info EVENTS eits-web
```

### Consumer Behavior on Restart
The consumer is truly durable. Restarting Phoenix will not replay any previously acknowledged messages. The NATS server maintains the delivery cursor.

### First-Time Startup
`deliver_policy: :new` means the consumer only receives messages published after its creation. Historical messages in the stream are ignored.

### Reset the Consumer
If the consumer needs to be rebuilt (e.g., to reprocess messages):
```bash
nats consumer rm EVENTS eits-web
```
Then restart Phoenix. The `ensure_consumer_exists/0` function will create a fresh consumer with `deliver_policy: :new`.

### Stream Must Exist
The JetStream consumer assumes the `EVENTS` stream already exists on the NATS server. The stream is not created by the application; it must be set up separately:
```bash
nats stream add EVENTS --subjects "events.>" --storage file --retention limits
```
