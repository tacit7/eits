# REST API v1

Base URL: `http://localhost:5000/api/v1`

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
curl -X POST localhost:5000/api/v1/sessions \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"abc-123","description":"implementing feature X","project_name":"web","model":"claude-sonnet-4-5-20250929"}'
```

---

### PATCH /sessions/:uuid

Update session status. Used by SessionEnd, Stop, and Compact hooks. Broadcasts on PubSub `"agent:working"` and `"agents"` topics.

For terminal states (`completed`, `failed`), `ended_at` is auto-set to now if not provided.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `uuid` | string | Session UUID from the POST response |

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | string | no | One of: `working`, `waiting`, `completed`, `failed` |
| `ended_at` | string | no | ISO 8601 timestamp. Auto-set for completed/failed |

**Response:** `200 OK`

```json
{
  "id": 42,
  "uuid": "session-uuid",
  "status": "completed",
  "ended_at": "2026-02-15T12:00:00Z"
}
```

**Example:**

```bash
curl -X PATCH localhost:5000/api/v1/sessions/abc-123 \
  -H 'Content-Type: application/json' \
  -d '{"status":"completed"}'
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
curl -X POST localhost:5000/api/v1/agents \
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
curl -X POST localhost:5000/api/v1/commits \
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
curl -X POST localhost:5000/api/v1/notes \
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
curl -X POST localhost:5000/api/v1/session-context \
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
curl -X POST localhost:5000/api/v1/push/subscriptions \
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
curl -X POST localhost:5000/api/v1/dm \
  -H 'Content-Type: application/json' \
  -d '{
    "from_session_id": 40,
    "to_session_id": 42,
    "body": "Can you check the test output?"
  }'
```

**Example (legacy format - still works):**

```bash
curl -X POST localhost:5000/api/v1/dm \
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

## Hook Integration

These endpoints map to Claude Code hooks:

| Hook | Endpoint | Notes |
|------|----------|-------|
| SessionStart | POST /sessions | Also replaces `i-start-session` MCP tool |
| SessionEnd | PATCH /sessions/:uuid | `status: "completed"` |
| Stop | PATCH /sessions/:uuid | `status: "failed"` |
| Compact | PATCH /sessions/:uuid | `status: "compacted"` (if needed) |
| PostToolUse (i-commits) | POST /commits | After git commit tool use |
| PostToolUse (i-note-add) | POST /notes | After note tool use |
| PostToolUse (i-save-session-context) | POST /session-context | After context save |
