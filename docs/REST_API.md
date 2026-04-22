# REST API v1

Base URL: `http://localhost:5001/api/v1`

All endpoints accept and return JSON. Set `Content-Type: application/json` on requests.

## Endpoints

### POST /sessions

Register a new session. Creates a ChatAgent (chat identity) and Agent (execution session). Broadcasts `{:agent_updated, agent}` on PubSub `"agents"` topic.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | yes | Claude Code session UUID |
| `description` | string | no | Session description |
| `agent_id` | string | no | Separate agent UUID. Defaults to `session_id` |
| `agent_description` | string | no | Overrides `description` for the ChatAgent record |
| `name` | string | no | Display name for the session |
| `project_id` | integer | no | Project ID (integer FK) |
| `project_name` | string | no | Resolved to `project_id` via `Projects.get_project_by_name/1` if `project_id` is absent |
| `model` | string | no | Model identifier, e.g. `claude-sonnet-4-5-20250929` |
| `provider` | string | no | AI provider. Defaults to `"claude"` |
| `worktree_path` | string | no | Git worktree path |

**Response:** `201 Created`

```json
{
  "id": 42,
  "uuid": "session-uuid",
  "agent_id": "agent-uuid",
  "agent_uuid": "agent-uuid",
  "status": "working"
}
```

**Example:**

```bash
curl -X POST localhost:5001/api/v1/sessions \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"abc-123","description":"implementing feature X","project_name":"web","model":"claude-sonnet-4-5-20250929"}'
```

---

### PATCH /sessions/:uuid

Update session status. Used by SessionEnd, Stop, and Compact hooks. Broadcasts on PubSub `"agent:working"` and `"agents"` topics.

For terminal states (`completed`, `failed`), `ended_at` is auto-set to now if not provided.

When transitioning away from `waiting` status (e.g., to `working`, `completed`, `failed`), `status_reason` is automatically cleared unless explicitly provided in the request.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `uuid` | string | Session UUID from the POST response |

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | string | no | One of: `working`, `idle`, `waiting`, `completed`, `failed` |
| `status_reason` | string | no | One of: `nil`, `"session_ended"`, `"sdk_completed"`. Auto-cleared when transitioning away from waiting |
| `ended_at` | string | no | ISO 8601 timestamp. Auto-set for completed/failed |

**Response:** `200 OK`

```json
{
  "id": 42,
  "uuid": "session-uuid",
  "status": "completed",
  "status_reason": null,
  "ended_at": "2026-02-15T12:00:00Z"
}
```

**Example:**

```bash
curl -X PATCH localhost:5001/api/v1/sessions/abc-123 \
  -H 'Content-Type: application/json' \
  -d '{"status":"completed"}'
```

---

### POST /sessions/:id/complete

Mark a session as completed with automatic team member status sync.

Accepts integer session ID or UUID string. Sets `status=completed`, `ended_at=now`, and syncs the session's team member status to `"done"` if the session belongs to a team.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `id` | string or integer | Session ID (UUID or integer) |

**Response:** `201 Created`

```json
{
  "success": true,
  "session_id": 42,
  "session_status": "completed",
  "member_synced": true
}
```

**Example:**

```bash
curl -X POST localhost:5001/api/v1/sessions/42/complete \
  -H 'Content-Type: application/json'

curl -X POST localhost:5001/api/v1/sessions/abc-123/complete \
  -H 'Content-Type: application/json'
```

---

### POST /sessions/:id/waiting

Mark a session as waiting (paused/blocked) with automatic team member status sync.

Accepts integer session ID or UUID string. Sets `status=waiting` and syncs the session's team member status to `"blocked"` if the session belongs to a team.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `id` | string or integer | Session ID (UUID or integer) |

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `reason` | string | no | Optional reason (e.g., `"waiting_for_approval"`, `"blocked_by_dependency"`) |

**Response:** `201 Created`

```json
{
  "success": true,
  "session_id": 42,
  "session_status": "waiting",
  "member_synced": true
}
```

**Example:**

```bash
curl -X POST localhost:5001/api/v1/sessions/42/waiting \
  -H 'Content-Type: application/json' \
  -d '{"reason": "waiting_for_approval"}'
```

---

### GET /sessions/:uuid

Fetch session detail with related resources (tasks, notes, commits).

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `uuid` | string or integer | Session UUID or integer ID |

**Response:** `200 OK`

```json
{
  "id": 42,
  "uuid": "session-uuid",
  "session_id": "session-uuid",
  "agent_id": "agent-uuid",
  "agent_int_id": 10,
  "project_id": 1,
  "status": "working",
  "status_reason": null,
  "name": "fix auth bug",
  "description": "fixing the oauth flow",
  "is_spawned": true,
  "initialized": true,
  "tasks": [
    {
      "id": 1,
      "title": "Add unit tests",
      "state": "In Progress",
      "state_id": 2
    }
  ],
  "recent_notes": [
    {
      "id": 5,
      "title": "Key finding",
      "body": "Found the root cause in session_controller.ex...",
      "starred": false,
      "created_at": "2026-03-15T10:30:00Z"
    }
  ],
  "recent_commits": [
    {
      "id": 1,
      "commit_hash": "abc123def456",
      "commit_message": "fix: add idle timeout to AgentWorker",
      "inserted_at": "2026-03-15T10:25:00Z"
    }
  ]
}
```

**Example:**

```bash
curl localhost:5001/api/v1/sessions/abc-123 \
  -H 'Authorization: Bearer <token>'
```

Or with integer ID:

```bash
curl localhost:5001/api/v1/sessions/42 \
  -H 'Authorization: Bearer <token>'
```

---

### POST /agents

Spawn a new Claude Code agent. Creates an Agent + Session, starts an AgentWorker, and sends the initial instructions as the first message.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `instructions` | string | yes | Initial prompt for the agent. Max 32,000 chars |
| `model` | string | no | `haiku`, `sonnet`, or `opus`. Defaults to `"haiku"` |
| `provider` | string | no | `claude` or `codex`. Defaults to `"claude"` |
| `project_id` | integer\|string | no | Project ID to associate with |
| `project_path` | string | no | Working directory for the Claude process |
| `worktree` | string | no | Git worktree branch name. Appends push+PR instructions to prompt |
| `effort_level` | string | no | Passed to Claude CLI as effort level |
| `parent_agent_id` | integer\|string | no | Integer ID of the parent agent |
| `parent_session_id` | integer\|string | no | Integer ID of the parent session |
| `agent` | string | no | Named agent persona passed to Claude CLI via `--agent` |
| `team_name` | string | no | Join this team on spawn. Team must exist |
| `member_name` | string | no | Alias within the team. Defaults to agent UUID |

**Response:** `201 Created`

```json
{
  "success": true,
  "message": "Agent spawned",
  "agent_id": "agent-uuid",
  "session_id": 42,
  "session_uuid": "session-uuid"
}
```

With `team_name`:

```json
{
  "success": true,
  "message": "Agent spawned",
  "agent_id": "agent-uuid",
  "session_id": 42,
  "session_uuid": "session-uuid",
  "team_id": 1,
  "team_name": "my-team",
  "member_name": "worker-1"
}
```

**Example:**

```bash
curl -X POST localhost:5001/api/v1/agents \
  -H 'Content-Type: application/json' \
  -d '{
    "instructions": "Fix the auth bug in session_controller.ex and run the tests",
    "model": "sonnet",
    "project_id": 1,
    "project_path": "/Users/me/projects/web",
    "parent_session_id": 1074
  }'
```

---

### POST /commits

Track one or more git commits. Looks up the Agent by UUID to get the integer `session_id` FK.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | yes | Agent/session UUID |
| `commit_hashes` | string[] | yes | List of commit hashes |
| `commit_messages` | string[] | no | Parallel list of commit messages |

**Response:** `201 Created` (or `207 Multi-Status` if partial failures)

```json
{
  "commits": [
    {"id": 1, "commit_hash": "abc123", "commit_message": "fix bug"}
  ],
  "errors": []
}
```

**Example:**

```bash
curl -X POST localhost:5001/api/v1/commits \
  -H 'Content-Type: application/json' \
  -d '{"agent_id":"abc-123","commit_hashes":["a1b2c3"],"commit_messages":["fix auth bug"]}'
```

---

### POST /notes

Add a note attached to a session, agent, or task.

Parent type plurals are normalized automatically: `"sessions"` -> `"session"`, `"agents"` -> `"agent"`, `"tasks"` -> `"task"`.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `parent_type` | string | yes | `session`, `agent`, or `task` (plurals accepted) |
| `parent_id` | string | yes | ID of the parent entity |
| `body` | string | yes | Note content (markdown) |
| `title` | string | no | Note title |
| `starred` | integer | no | `0` or `1`. Defaults to `0` |

**Response:** `201 Created`

```json
{
  "id": 10,
  "parent_type": "session",
  "parent_id": "42",
  "title": null,
  "body": "interesting finding here",
  "starred": 0
}
```

**Example:**

```bash
curl -X POST localhost:5001/api/v1/notes \
  -H 'Content-Type: application/json' \
  -d '{"parent_type":"sessions","parent_id":"42","body":"found the root cause"}'
```

---

### POST /session-context

Save or update session context (markdown). Upserts based on session_id. Looks up the Agent by UUID to resolve integer IDs.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | yes | Agent/session UUID |
| `context` | string | yes | Markdown context content |

**Response:** `201 Created`

```json
{
  "id": 5,
  "agent_id": 7,
  "session_id": 42,
  "context": "# Session Context\n\nWorking on..."
}
```

**Example:**

```bash
curl -X POST localhost:5001/api/v1/session-context \
  -H 'Content-Type: application/json' \
  -d '{"agent_id":"abc-123","context":"# Context\n\nKey findings..."}'
```

---

## Error Responses

All errors return JSON with an `error` field and optional `details`:

**400 Bad Request** - Missing required field:
```json
{"error": "session_id is required"}
```

**404 Not Found** - Entity lookup failed:
```json
{"error": "Agent not found"}
```

**422 Unprocessable Entity** - Validation failure:
```json
{"error": "Failed to create session", "details": {"status": ["is invalid"]}}
```

**Generic error responses:**

Controllers can return errors in these formats, which FallbackController handles:

- `{:error, reason}` — 400 Bad Request with reason as error message
- `{:error, status, reason}` — Custom HTTP status with reason (e.g. `{:error, :unauthorized, "Invalid token"}`)
- `{:error, status}` — Custom HTTP status with status atom as error message (e.g. `{:error, :forbidden}` → `{"error": "forbidden"}`)
- `{:error, changeset}` — 422 Unprocessable Entity with changeset errors

## PubSub Topics

These endpoints broadcast events for real-time LiveView updates:

| Topic | Event | Triggered by |
|-------|-------|-------------|
| `"agents"` | `{:agent_updated, agent}` | POST /sessions, PATCH /sessions/:uuid |
| `"agent:working"` | `{:agent_working, agent}` | PATCH with non-terminal status |
| `"agent:working"` | `{:agent_stopped, agent}` | PATCH with completed/failed |

### POST /webhooks/gitea

Receive Gitea webhook events for PR review automation.

**Webhook events supported:**
- `pull_request` (opened) — spawns a Codex review agent
- `issue_comment` (created on PR) — routes DM to the Claude session embedded in PR body

**Request body:**

| Field | Type | Description |
|-------|------|-------------|
| `action` | string | `opened` or `created` (issue_comment) |
| `pull_request` | object | PR details (title, body, head.sha, base.ref, diff_url) |
| `issue` | object | Issue/PR metadata (number, title) |
| `comment` | object | Comment object (body, created_at) |
| `repository` | object | Repository details (full_name, clone_url) |

**HMAC authentication:**

Gitea webhook must be signed with `GITEA_WEBHOOK_SECRET` env var. Plug validates `X-Gitea-Signature` header against raw body:

```
sha256_hmac(raw_body, GITEA_WEBHOOK_SECRET)
```

The signature header can be in two formats:
- **New format**: `X-Gitea-Signature: sha256=<hex_digest>`
- **Legacy format**: Raw hex digest

Both formats are supported. Signature comparison is case-insensitive.

**Validation requirements:**
- `repository.full_name` is required; returns `400 Bad Request` if missing
- `project_path` must be configured; returns `500 Internal Server Error` if not configured or derivable
- Requests without valid signature return `401 Unauthorized`
- In production, unsigned requests fail closed (return 403) when `GITEA_WEBHOOK_SECRET` is missing
- In development, unsigned requests can be allowed via `allow_unsigned_webhooks` config flag

**Response:** `202 Accepted` (async processing)

---

### POST /api/v1/push/subscriptions

Register a browser for web push notifications.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `subscription` | object | yes | Web Push subscription object from service worker |
| `subscription.endpoint` | string | yes | Push service endpoint URL |
| `subscription.keys` | object | yes | Encryption keys (p256dh, auth) |

**Response:** `201 Created`

```json
{
  "id": 1,
  "endpoint": "https://fcm.googleapis.com/...",
  "inserted_at": "2026-03-12T10:30:00Z"
}
```

**Example:**

```bash
# After service worker registers
curl -X POST localhost:5001/api/v1/push/subscriptions \
  -H 'Content-Type: application/json' \
  -d @subscription.json  # from navigator.serviceWorker.ready.then(reg => reg.pushManager.getSubscription())
```

---

### GET /api/v1/push/subscriptions

List all registered push subscriptions for the current user.

**Response:** `200 OK`

```json
[
  {
    "id": 1,
    "endpoint": "https://fcm.googleapis.com/...",
    "inserted_at": "2026-03-12T10:30:00Z"
  }
]
```

---

### POST /api/v1/dm

Send a message to an agent session. Rate-limited to protect against message injection flooding.

Messages can only be delivered to sessions with `status` in `["working", "idle"]`. Attempts to DM sessions with other statuses (e.g., `waiting`, `completed`, `failed`) return `422 Unprocessable Entity`.

**Request body (current format):**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `from_session_id` | integer \| string | yes | Sender session ID (int) or UUID (string) |
| `to_session_id` | integer \| string | yes | Recipient session ID (int) or UUID (string) |
| `body` | string | yes | Message content (markdown) |

**Legacy format (backward compatible):**

| Field | Type | Deprecated | Description |
|-------|------|------------|-------------|
| `session_id` | integer | yes | Use `to_session_id` instead |
| `sender_id` | string | yes | Use `from_session_id` instead |
| `content` | string | yes | Use `body` instead |
| `target_session_id` | integer | yes | Use `to_session_id` instead |

**Response:** `201 Created`

```json
{
  "id": 123,
  "from_session_id": 40,
  "to_session_id": 42,
  "body": "Looking at the error logs...",
  "from_session_uuid": "abc-123",
  "inserted_at": "2026-03-17T10:30:00Z"
}
```

**Message body format sent to agent:**

When a DM is routed to an agent, the body includes sender context:

```
DM from:<sender_name> (session:<sender_uuid>) <original_message>
```

Example: `DM from:Developer (session:abc-123) Can you check the test output?`

This allows agents to reply to the correct session via `eits dm` command.

**Duplicate detection (idempotency):**

If an identical DM body was already delivered to the same recipient session within the last 30 seconds, the endpoint returns `201 Created` with the **original** message's `message_id` and `message_uuid` instead of inserting a duplicate. This improves broadcast/DM reliability under retries — callers can safely re-POST without creating duplicate messages.

No new row is written and no PubSub event is re-broadcast on duplicate hits. The 24-hour unlinked-message search (`Messages.find_unlinked_message/3`) uses the same deduplicator with a wider window for linking inbound replies.

**Rate limiting:**

- 30 requests per minute per `from_session_id`
- Exceeding limit returns `429 Too Many Requests`:

```json
{
  "error": "Rate limit exceeded",
  "retry_after": 5
}
```

**Example (current format):**

```bash
curl -X POST localhost:5001/api/v1/dm \
  -H 'Content-Type: application/json' \
  -d '{
    "from_session_id": 40,
    "to_session_id": 42,
    "body": "Can you check the test output?"
  }'
```

**Example (legacy format - still works):**

```bash
curl -X POST localhost:5001/api/v1/dm \
  -H 'Content-Type: application/json' \
  -d '{
    "session_id": 42,
    "sender_id": "user-123",
    "content": "Can you check the test output?"
  }'
```

---

### GET /api/v1/channels

List available chat channels.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `project_id` | integer | no | Filter by project ID |

**Response:** `200 OK`

```json
{
  "success": true,
  "message": "2 channel(s) found",
  "channels": [
    {
      "id": "1",
      "name": "general",
      "description": null,
      "channel_type": "public",
      "project_id": 1
    }
  ]
}
```

**Example:**

```bash
eits channels list
eits channels list --project 1
```

---

### GET /api/v1/channels/:channel_id/messages

Get recent messages for a channel.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `limit` | integer | no | Number of messages (default 20, max 200) |

**Response:** `200 OK`

```json
{
  "success": true,
  "channel_id": "1",
  "count": 3,
  "messages": [
    {
      "id": 402400,
      "uuid": "b49fcd7e-...",
      "session_id": 1172,
      "session_name": "arch deep dive",
      "sender_role": "agent",
      "provider": "claude",
      "body": "Message content here...",
      "status": "delivered",
      "inserted_at": "2026-03-17T10:02:57Z"
    }
  ]
}
```

**Example:**

```bash
eits channels messages 1
eits channels messages 1 -n 5
```

---

### POST /api/v1/channels

Create a new channel.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Channel name |
| `project_id` | integer | no | Project ID to associate with |
| `channel_type` | string | no | Channel type (default: `"public"`) |
| `description` | string | no | Channel description |
| `session_id` | string | no | Session ID (integer or UUID) |

**Response:** `201 Created`

```json
{
  "success": true,
  "id": "ch-1",
  "name": "dev-updates",
  "description": "Development updates channel",
  "channel_type": "public",
  "project_id": 1
}
```

**Example:**

```bash
eits channels create --name "dev-updates" --project 1 --description "Development updates"
```

---

### POST /api/v1/channels/:id/members

Add a member to a channel.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | yes | Session ID (integer or UUID) |
| `notifications` | string | no | Notification setting (`"all"`, `"none"`, default: `"none"`) |

**Response:** `201 Created`

```json
{
  "channel_id": "ch-1",
  "session_id": 42,
  "notifications": "all"
}
```

---

### DELETE /api/v1/channels/:id/members/:session_id

Remove a member from a channel.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `id` | string | Channel ID |
| `session_id` | string or integer | Session ID (integer or UUID) |

**Response:** `200 OK`

```json
{
  "success": true,
  "message": "Member removed"
}
```

---

### POST /api/v1/channels/:channel_id/messages

Send a message to a channel.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | yes | Session ID (integer or UUID) |
| `body` | string | yes | Message content |
| `sender_role` | string | no | Default: `"agent"` |
| `recipient_role` | string | no | Default: `"user"` |
| `provider` | string | no | Default: `"claude"` |
| `broadcast_to_team_id` | integer | no | When present, fans out DMs to all team members with active sessions (excluding sender) after message is persisted |

**Response:** `201 Created`

```json
{
  "success": true,
  "message": "Message sent",
  "message_id": "12345"
}
```

**Example:**

```bash
eits channels send 1 --session 1179 --body "hello from CLI"
```

---

---

### GET /api/v1/sessions (list with filters)

List sessions with optional filtering. Supports full-text search, name filters, project filtering, and optional task embedding.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `q` | string | no | Full-text search query (searches session name, description, notes) |
| `project_id` | integer | no | Filter by project ID |
| `status` | string | no | Filter by status (`working`, `idle`, `waiting`, `completed`, `failed`) |
| `name` | string | no | Filter by session name (case-insensitive ilike match) |
| `with_tasks` | boolean | no | When `true`, embeds task list per session (id, title, state_id, state) |
| `include_archived` | boolean | no | Include archived sessions (default false) |
| `limit` | integer | no | Max results (default 20) |

**Response:** `200 OK`

```json
{
  "success": true,
  "message": "Found 2 session(s)",
  "results": [
    {
      "id": 42,
      "uuid": "abc-123",
      "name": "fix auth bug",
      "description": "fixing the oauth flow",
      "status": "working",
      "status_reason": null,
      "tasks": [
        {
          "id": 1,
          "title": "Add unit tests",
          "state_id": 2,
          "state": "In Progress"
        }
      ]
    }
  ]
}
```

**Example:**

```bash
eits sessions list --name "auth" --with-tasks
eits sessions list --project 1 --include-archived
eits sessions list --name "deploy"
```

---

### GET /api/v1/sessions/:session_id/timer

Get the active timer for a session, if any.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `session_id` | string or integer | Session ID (UUID or integer). Returns 404 if session not found |

**Response:** `200 OK` (with timer)

```json
{
  "success": true,
  "timer": {
    "mode": "once",
    "interval_ms": 300000,
    "message": "Check on task progress",
    "started_at": "2026-04-19T12:30:00Z",
    "next_fire_at": "2026-04-19T12:35:00Z"
  }
}
```

**Response:** `404 Not Found` (no active timer)

```json
{
  "error": "no active timer for this session"
}
```

**Example:**

```bash
curl localhost:5001/api/v1/sessions/42/timer
curl localhost:5001/api/v1/sessions/abc-123/timer  # UUID also works
```

---

### POST /api/v1/sessions/:session_id/timer

Schedule a wake-up timer for a session. Replaces any existing timer for that session.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `session_id` | string or integer | Session ID (UUID or integer). Returns 404 if session not found |

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `delay_ms` | integer | no | Delay in milliseconds (min 100). Takes precedence over `preset` if both supplied |
| `preset` | string | no | Preset delay: `"5m"`, `"10m"`, `"15m"`, `"30m"`, `"1h"`. Used if `delay_ms` is absent. Returns 400 if invalid |
| `mode` | string | no | Timer mode: `"once"` (default) or `"repeating"`. Returns 400 if invalid |
| `message` | string | no | Optional message override. Whitespace-only messages fall back to default. Message is trimmed before use |

**Response:** `201 Created`

```json
{
  "success": true,
  "action": "scheduled",
  "timer": {
    "mode": "once",
    "interval_ms": 300000,
    "message": "Check on task progress",
    "started_at": "2026-04-19T12:30:00Z",
    "next_fire_at": "2026-04-19T12:35:00Z"
  }
}
```

When replacing an existing timer, `action` is `"replaced"` instead of `"scheduled"`.

**Error responses:**

- `400 Bad Request` — Invalid delay_ms (< 100), missing both delay_ms and preset, invalid mode, or invalid preset
- `404 Not Found` — Session not found

**Example:**

```bash
# With preset
curl -X POST localhost:5001/api/v1/sessions/42/timer \
  -H 'Content-Type: application/json' \
  -d '{"preset": "5m", "mode": "once"}'

# With custom delay and message
curl -X POST localhost:5001/api/v1/sessions/42/timer \
  -H 'Content-Type: application/json' \
  -d '{"delay_ms": 600000, "message": "Deploy to staging", "mode": "once"}'
```

---

### DELETE /api/v1/sessions/:session_id/timer

Cancel the active timer for a session.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `session_id` | string or integer | Session ID (UUID or integer) |

**Response:** `200 OK`

```json
{
  "success": true,
  "message": "Timer cancelled"
}
```

---

### PATCH /api/v1/teams/:id

Update team metadata.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | no | Team name |
| `description` | string | no | Team description |

**Response:** `200 OK`

```json
{
  "id": 1,
  "name": "Platform Team",
  "description": "Core platform development",
  "updated_at": "2026-04-19T12:00:00Z"
}
```

**Example:**

```bash
eits teams update 1 --name "Platform Team" --description "Core platform dev"
```

---

### POST /api/v1/teams/:id/broadcast

Broadcast a message to all team members with active sessions.

Fans out direct messages to all team members, excluding the sender. Used for team-wide announcements or status updates.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `body` | string | yes | Message content |
| `from_session_id` | string or integer | no | Sender session ID (defaults to request context) |

**Response:** `200 OK`

```json
{
  "success": true,
  "team_id": 1,
  "sent_count": 5,
  "failed": 0
}
```

**Example:**

```bash
eits teams broadcast 1 --body "Deploying release v2.0 in 10 minutes"
```

---

### POST /api/v1/tasks/search

Search for tasks across projects with optional filtering.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `query` | string | yes | Search query (searches task titles, descriptions, and body) |
| `project_id` | integer | no | Filter to a specific project |
| `state` | string | no | Filter by state (e.g., `"In Progress"`, `"To Do"`, `"Done"`) |
| `limit` | integer | no | Max results (default 20, max 200) |

**Response:** `200 OK`

```json
{
  "success": true,
  "message": "Found 3 task(s)",
  "results": [
    {
      "id": 1,
      "title": "Fix auth bug",
      "state": "In Progress",
      "state_id": 2,
      "project_id": 1,
      "description": "OAuth flow is broken"
    }
  ]
}
```

**Example:**

```bash
eits tasks search "auth bug" --project 1 --state "In Progress"
```

---

### POST /api/v1/tasks/:id/tags

Add tags to a task.

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `tag_names` | string[] | yes | List of tag names to add |

**Response:** `201 Created`

```json
{
  "success": true,
  "task_id": 1,
  "tags": [
    {"id": 1, "name": "bug"},
    {"id": 2, "name": "urgent"}
  ]
}
```

---

### GET /api/v1/tasks/:id/sessions

Get all sessions linked to a task.

**Response:** `200 OK`

```json
{
  "task_id": 1,
  "sessions": [
    {
      "id": 42,
      "uuid": "abc-123",
      "name": "fix auth bug",
      "status": "working"
    }
  ]
}
```

**Example:**

```bash
eits tasks sessions 1
```

---

### GET /api/browser/sessions

List sessions for UI-internal reads (e.g. command palette "Go to Session..." submenu). Authenticates via **session cookie** instead of Bearer token, so browser `fetch()` calls work without needing an API key.

**Why this exists:** `GET /api/v1/sessions` requires `Authorization: Bearer <token>`. Browser-side JavaScript (LiveView hooks) cannot attach a Bearer token — it only has the session cookie. This endpoint sits under a separate `browser_json` pipeline that validates the cookie via `SessionAuth` plug instead.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `q` | string | no | Full-text search query |
| `project_id` | integer | no | Filter to sessions belonging to this project |
| `status` | string | no | Filter by status (e.g. `active`, `working`, `completed`) |
| `limit` | integer | no | Max results to return (default 20) |

**Response:** `200 OK`

```json
{
  "success": true,
  "message": "Found 3 session(s)",
  "results": [
    {
      "id": 42,
      "uuid": "abc-123",
      "name": "fix auth bug",
      "description": "fixing the oauth flow",
      "status": "working"
    }
  ]
}
```

**Authentication:** Session cookie (set by Phoenix on browser login). No `Authorization` header needed.

**Example (from browser JS):**

```js
const res = await fetch('/api/browser/sessions?project_id=1&limit=50');
const { results } = await res.json();
```

**Note:** This endpoint is intentionally read-only and scoped to UI-internal use. For programmatic/agent access, use `GET /api/v1/sessions` with a Bearer token.

---

## EITS-CMD dm: numeric session ID support

The `dm --to` directive (commit ee6cacc) accepts both a UUID and a numeric session ID as the target. Agents no longer need the full UUID — the simpler `EITS_SESSION_ID` integer env var works directly.

**Both formats are equivalent:**

```
EITS-CMD: dm --to 16e6d223-14b8-4e21-8461-8b5c2303fa8c --message "done"
EITS-CMD: dm --to 1804 --message "done"
```

The dispatcher resolves an integer string to a session UUID internally before routing the DM.

**Typical agent usage:**

```
# Use EITS_SESSION_ID (integer) from the spawn context — simpler than EITS_SESSION_UUID
EITS-CMD: dm --to $EITS_SESSION_ID --message "task complete"
```

This also applies to the REST API `POST /api/v1/dm` endpoint — `to_session_id` has accepted both formats since the same commit.

---

### POST /api/v1/iam/decide

Evaluate a Claude Code hook payload against IAM policies and return the hook-protocol JSON response.

This endpoint is **unauthenticated** — hook scripts run in the Claude CLI process environment with no user session context and cannot send Bearer tokens.

**Request body:**

Raw Claude Code hook payload (JSON object). The endpoint normalizes the payload to extract:
- `event` — Hook event type (`"PreToolUse"`, `"PostToolUse"`, `"UserPromptSubmit"`, `"Stop"`)
- `session_uuid` — Session UUID (if available)
- `tool` — Tool name being evaluated (for PreToolUse)
- `resource_path` — File path or resource identifier
- `project_id` — Project ID (from session or path resolution)
- `project_path` — Project directory path
- `agent_type` — Agent type from session

**Response:** `200 OK` — Hook-protocol JSON

Hook response shape depends on event type:

**PreToolUse (permission decision):**

```json
{
  "permissionDecision": "allow" | "deny",
  "instructions": ["Instruction text from matching policy"],
  "hookSpecificOutput": null
}
```

**PostToolUse / UserPromptSubmit:**

```json
{
  "continue": true | false,
  "additionalContext": "Instruction text from matching policy or null",
  "hookSpecificOutput": null
}
```

For `UserPromptSubmit`, use `suppressUserPrompt` + `hookSpecificOutput.userPrompt` to replace the prompt:

```json
{
  "continue": true,
  "suppressUserPrompt": true,
  "hookSpecificOutput": {
    "userPrompt": "Modified prompt text"
  }
}
```

**Stop:**

```json
{
  "continue": true | false,
  "additionalContext": "Instruction text from matching policy or null"
}
```

**Fire-and-forget audit:**

Decision evaluations are written asynchronously to the `iam_decisions` table with:
- Decision ID, session UUID, event type, project info
- Tool and resource path
- Permission result and winning policy
- Instructions snapshot
- Evaluation duration (microseconds)
- Raw payload

**Example hook script (curl):**

```bash
# Claude Code hook: PreToolUse
# Payload comes from Claude CLI with Bearer token not available
curl -X POST http://localhost:5001/api/v1/iam/decide \
  -H 'Content-Type: application/json' \
  -d '{
    "event": "PreToolUse",
    "tool": "bash",
    "session_uuid": "abc-123",
    "resource_path": "/Users/me/project/src",
    "project_id": 1,
    "project_path": "/Users/me/project"
  }'
```

---

## Hook Integration

These endpoints map to Claude Code hooks:

| Hook | Endpoint | Notes |
|------|----------|-------|
| SessionStart | POST /sessions | Also replaces `i-start-session` MCP tool |
| SessionEnd | PATCH /sessions/:uuid | `status: "completed"` |
| Stop | PATCH /sessions/:uuid | `status: "failed"` |
| Compact | PATCH /sessions/:uuid | `status: "compacted"` (if needed) |
| PreToolUse (IAM policy evaluation) | POST /api/v1/iam/decide | Evaluate tool permission against policies |
| PostToolUse (IAM policy evaluation) | POST /api/v1/iam/decide | Evaluate post-tool action against policies |
| UserPromptSubmit (IAM policy evaluation) | POST /api/v1/iam/decide | Evaluate prompt against sanitization policies |
| Stop (IAM policy evaluation) | POST /api/v1/iam/decide | Evaluate stop action against policies |
| PostToolUse (i-commits) | POST /commits | After git commit tool use |
| PostToolUse (i-note-add) | POST /notes | After note tool use |
| PostToolUse (i-save-session-context) | POST /session-context | After context save |
