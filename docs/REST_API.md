# REST API v1

Base URL: `http://localhost:5001/api/v1`

All endpoints accept and return JSON. Set `Content-Type: application/json` on requests.

## Endpoints

### GET /api/v1/health

Lightweight health check endpoint for monitoring service availability.

**Response:** `200 OK`

```json
{
  "status": "ok"
}
```

**Example:**

```bash
curl localhost:5001/api/v1/health
```

---

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
  "project_id": 1,
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
| `status_reason` | string | no | One of: `nil`, `"session_ended"`, `"sdk_completed"`, `"zombie_swept"`, `"billing_error"`, `"authentication_error"`, `"rate_limit_error"`, `"watchdog_timeout"`, `"retry_exhausted"`. Auto-cleared when transitioning away from waiting. Error values are normally set by the AgentWorker on systemic failure, not by API clients — they drive the red failure-tier badges in the session UI |
| `ended_at` | string | no | ISO 8601 timestamp. Auto-set for completed/failed |
| `read_only` | boolean | no | Session intent: `true` for read-only (review mode), `false` for work mode |

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

**Response:** `200 OK`

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

### POST /sessions/:id/reopen

Reopen a completed or failed session. Clears `ended_at` and sets `status` to `idle` so the session can accept new task updates and DMs.

Accepts integer session ID or UUID string.

Use when a resume hook fails to reset status, or when an orchestrator needs to post work against an already-ended session.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `uuid` | string or integer | Session ID (UUID or integer) |

**Response:** `200 OK`

```json
{
  "success": true,
  "session_id": 42,
  "session_status": "idle",
  "member_synced": false
}
```

**Example:**

```bash
curl -X POST localhost:5001/api/v1/sessions/42/reopen \
  -H 'Content-Type: application/json'

curl -X POST localhost:5001/api/v1/sessions/abc-123/reopen \
  -H 'Content-Type: application/json'

# CLI
eits sessions reopen abc-123
eits sessions reopen self   # uses EITS_SESSION_UUID
```

---

### POST /sessions/:id/waiting

Mark a session as waiting (paused/blocked) with automatic team member status sync.

Accepts integer session ID or UUID string. Sets `status=waiting` and syncs the session's team member status to `"blocked"` if the session belongs to a team.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `id` | string or integer | Session ID (UUID or integer) |

**Response:** `200 OK`

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
  -H 'Content-Type: application/json'

curl -X POST localhost:5001/api/v1/sessions/abc-123/waiting \
  -H 'Content-Type: application/json'
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
  "worktree_path": "/path/to/project/.claude/worktrees/fix-auth-bug",
  "branch_name": "worktree-fix-auth-bug",
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

**Notes:**
- `worktree_path` — absolute path stored in `sessions.git_worktree_path`; `null` if the session was not started in a worktree.
- `branch_name` — resolved at request time via `git symbolic-ref --short HEAD` inside the worktree path; `null` if `worktree_path` is null or the path no longer exists.

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

### GET /api/v1/sessions/:uuid/tasks

List tasks linked to a session (path-based alias for `GET /api/v1/tasks?session_id=`).

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `uuid` | string | Session UUID or integer ID |

**Query params (same as GET /api/v1/tasks):**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `limit` | integer | no | Max results (default 50) |
| `state_id` | integer | no | Filter by workflow state ID |

**Response:** `200 OK`

```json
{
  "success": true,
  "message": "2 task(s)",
  "tasks": [
    {
      "id": 1,
      "title": "Add unit tests",
      "state": "In Progress",
      "state_id": 2,
      "project_id": 1,
      "created_at": "2026-04-10T10:00:00Z",
      "updated_at": "2026-04-15T14:30:00Z"
    }
  ]
}
```

**Example:**

```bash
curl localhost:5001/api/v1/sessions/abc-123/tasks
curl localhost:5001/api/v1/sessions/42/tasks?limit=10
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
| `parent_agent_id` | integer | no | Integer ID of the parent agent (integer only; UUID strings rejected) |
| `parent_session_id` | integer\|string | no | Parent session ID — accepts integer ID or UUID string |
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

### GET /api/v1/agents/activity

Get activity rollup for an agent since a given datetime. Returns tasks (categorized by state), commits, and sessions created/updated since the cutoff, with summary counts.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_uuid` | string | yes | Agent UUID |
| `since` | string | no | Duration string (e.g. `24h`, `7d`, `1m`) or ISO 8601 datetime. Defaults to `"24h"` when omitted |

**Response:** `200 OK`

```json
{
  "success": true,
  "agent_uuid": "agent-uuid",
  "since": "2026-04-15T10:00:00Z",
  "window_start": "2026-04-14T10:00:00Z",
  "tasks": {
    "done": [
      {
        "id": 1,
        "title": "Add unit tests",
        "state": "Done",
        "state_id": 4
      }
    ],
    "in_review": [],
    "in_progress": [
      {
        "id": 2,
        "title": "Fix auth bug",
        "state": "In Progress",
        "state_id": 2
      }
    ],
    "stale": []
  },
  "commits": [
    {
      "hash": "abc123def456",
      "message": "fix auth bug",
      "window_start": "2026-04-14T10:00:00Z",
      "session_id": 42
    }
  ],
  "sessions": [
    {
      "uuid": "session-uuid",
      "id": 42,
      "name": "fix auth",
      "status": "working"
    }
  ],
  "summary": {
    "task_count": 2,
    "commit_count": 1,
    "session_count": 1
  }
}
```

**Example:**

```bash
curl 'localhost:5001/api/v1/agents/activity?agent_uuid=abc-123&since=24h'
curl 'localhost:5001/api/v1/agents/activity?agent_uuid=abc-123&since=2026-04-15T10:00:00Z'
eits agents activity abc-123 --since 24h
```

---

### GET /api/v1/agents

List agents with optional filtering by project, status, or activity recency. Status filtering is pushed to the database query for efficient filtering.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `project_id` | integer | no | Filter to agents in a specific project |
| `status` | string | no | Filter by status (e.g. `"working"`, `"idle"`); pushed to DB query |
| `active_since` | string | no | ISO 8601 datetime. Returns only agents with session activity at or after this time |
| `limit` | integer | no | Max results (default 20) |

**Response:** `200 OK`

```json
{
  "success": true,
  "agents": [
    {
      "id": 1,
      "uuid": "agent-uuid",
      "name": "code-review-agent",
      "status": "working",
      "type": "general-purpose",
      "created_at": "2026-04-10T10:00:00Z"
    }
  ]
}
```

**Example:**

```bash
curl 'localhost:5001/api/v1/agents?project_id=1&limit=10'
curl 'localhost:5001/api/v1/agents?active_since=2026-04-15T10:00:00Z'
eits agents list --active-since 24h
```

---

### GET /api/v1/commits

List commits for a session or agent with optional filtering.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | no | Session UUID to list commits for |
| `agent_id` | string | no | Agent UUID to list commits for |
| `limit` | integer | no | Max results (default 20, max 100) |
| `since_hash` | string | no | Return only commits newer than this hash; includes `since_hash_found` in response |

**Response:** `200 OK`

```json
{
  "success": true,
  "commits": [
    {"id": 1, "commit_hash": "abc123def456", "commit_message": "fix bug"}
  ]
}
```

With `since_hash`:

```json
{
  "success": true,
  "commits": [...],
  "since_hash": "abc123",
  "since_hash_found": true
}
```

**Example:**

```bash
curl localhost:5001/api/v1/commits?session_id=abc-123&limit=10
curl localhost:5001/api/v1/commits?session_id=abc-123&since_hash=a1b2c3
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

**Response:** `201 Created` (or `207 Multi-Status` if some duplicates)

Distinguishes created commits from duplicates. Duplicate hashes (detected via `on_conflict: :nothing`) are returned separately with `status: "duplicate"`.

```json
{
  "commits": [
    {"id": 1, "commit_hash": "abc123", "commit_message": "fix bug", "status": "created"}
  ],
  "duplicates": [
    {"commit_hash": "existing123", "status": "duplicate"}
  ],
  "errors": [],
  "already_tracked": false
}
```

`already_tracked` is `true` when all submitted hashes were duplicates (i.e. `duplicates` is non-empty and both `commits` and `errors` are empty). Lets callers detect the already-tracked case without inspecting array lengths.

```json
{
  "commits": [],
  "duplicates": [{"commit_hash": "abc123", "status": "duplicate"}],
  "errors": [],
  "already_tracked": true
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

### PATCH /api/v1/notes/:id

Update an existing note (body, title, starred, parent_type, parent_id).

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `id` | integer | Note ID |

**Request body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `body` | string | no | Note content (markdown) |
| `title` | string | no | Note title |
| `starred` | integer | no | `0` or `1` |
| `parent_type` | string | no | `session`, `agent`, or `task` (plurals normalized) |
| `parent_id` | string | no | ID of the parent entity |

**Response:** `200 OK`

```json
{
  "id": 10,
  "parent_type": "session",
  "parent_id": "42",
  "title": "Updated title",
  "body": "updated content",
  "starred": 1
}
```

**Example:**

```bash
curl -X PATCH localhost:5001/api/v1/notes/10 \
  -H 'Content-Type: application/json' \
  -d '{"body":"updated finding","title":"New title","starred":1}'

# Reparent a note
curl -X PATCH localhost:5001/api/v1/notes/10 \
  -H 'Content-Type: application/json' \
  -d '{"parent_type":"task","parent_id":"42"}'
```

---

### GET /api/v1/notes

List notes attached to a session or task with optional starred filtering. Starred filtering is pushed to the database query for efficient filtering.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | no | Filter to notes attached to a specific session (UUID or integer ID) |
| `task_id` | integer | no | Filter to notes attached to a specific task |
| `starred` | integer | no | Filter by starred status; pass `1` to return only starred notes, `0` for unstarred (filtering pushed to DB query) |
| `q` | string | no | Full-text search query (searches note title and body) |
| `limit` | integer | no | Max results (default 50) |

**Response:** `200 OK`

```json
{
  "success": true,
  "notes": [
    {
      "id": 10,
      "parent_type": "session",
      "parent_id": "42",
      "title": "Key finding",
      "body": "Found the root cause in session_controller.ex...",
      "starred": 1,
      "created_at": "2026-03-15T10:30:00Z"
    }
  ]
}
```

**Example:**

```bash
curl 'localhost:5001/api/v1/notes?session_id=42&starred=1'
curl 'localhost:5001/api/v1/notes?task_id=1'
curl 'localhost:5001/api/v1/notes?session_id=42&q=authentication'
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

### GET /api/v1/messages/search

Search messages across all sessions with optional filtering.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `q` | string | yes | Search query (full-text search on message body) |
| `session_id` | string or integer | no | Filter to messages from a specific session (UUID or integer ID) |
| `limit` | integer | no | Max results (default 10, max 100) |

**Response:** `200 OK`

```json
{
  "success": true,
  "query": "authentication bug",
  "count": 2,
  "messages": [
    {
      "id": 123,
      "session_id": 42,
      "session_uuid": "session-uuid",
      "session_name": "fix auth",
      "role": "agent",
      "body_excerpt": "Found the authentication bug in the oauth flow...",
      "inserted_at": "2026-04-20T10:30:00Z"
    }
  ]
}
```

**Example:**

```bash
curl 'localhost:5001/api/v1/messages/search?q=authentication%20bug&limit=20'
curl 'localhost:5001/api/v1/messages/search?q=oauth&session_id=42'
eits messages search "auth bug" --limit 20
```

---

### GET /api/v1/dm

List inbound messages (DMs) to a session with optional sender and time filtering.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `session` or `session_id` | string or integer | yes | Recipient session ID (UUID or integer) |
| `from` or `from_session_id` | string or integer | no | Filter by sender session ID (UUID or integer) |
| `since` | string | no | ISO 8601 datetime; returns only messages with `inserted_at` after this time |
| `limit` | integer | no | Max results (default 20, max 100) |

**Response:** `200 OK`

```json
{
  "session_id": 42,
  "session_uuid": "abc-123",
  "count": 2,
  "filter_from": null,
  "messages": [
    {
      "id": 123,
      "uuid": "msg-uuid",
      "body": "Looking at the error logs...",
      "from_session_id": 40,
      "to_session_id": 42,
      "inserted_at": "2026-03-17T10:30:00Z"
    }
  ]
}
```

With `from` filter:

```json
{
  "session_id": 42,
  "session_uuid": "abc-123",
  "count": 1,
  "filter_from": "40",
  "messages": [...]
}
```

**Example:**

```bash
curl localhost:5001/api/v1/dm?session=42&limit=10
curl localhost:5001/api/v1/dm?session=abc-123&from=40
curl localhost:5001/api/v1/dm?session_id=42&from_session_id=sender-uuid
curl localhost:5001/api/v1/dm?session=42&since=2026-03-17T10:00:00Z
eits dm inbox --session 42 --since 2026-03-17T10:00:00Z
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
| `metadata` | object | no | Structured JSON metadata. Merged with auto-generated context (sender_name, from_session_uuid, to_session_uuid, response_required). Supplied fields override auto-generated ones. |

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
  "success": true,
  "reachable": true,
  "message": "DM delivered to session 42",
  "message_id": "123",
  "message_uuid": "msg-uuid",
  "from_session_id": 40,
  "to_session_id": 42,
  "inserted_at": "2026-03-17T10:30:00Z"
}
```

`reachable: true` indicates the target session is in a receivable status (`working` or `idle`). Future implementations may support queuing to `waiting` sessions.

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
- Orchestrator role grants 5x burst ceiling: send `x-eits-role: orchestrator` header for a separate 150 req/min bucket
- Exceeding limit returns `429 Too Many Requests`:

```json
{
  "error": "Rate limit exceeded",
  "retry_after": 5
}
```

Orchestrator bursts bypass the regular per-IP limit and use a separate bucket to avoid DM flooding starving orchestrator queue operations.

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

**Example (with metadata for structured agent context):**

```bash
curl -X POST localhost:5001/api/v1/dm \
  -H 'Content-Type: application/json' \
  -d '{
    "from_session_id": 40,
    "to_session_id": 42,
    "body": "Please review the PR",
    "metadata": {
      "action": "review",
      "pr_number": 149,
      "target_branch": "main",
      "deadline": "2026-04-29T17:00:00Z"
    }
  }'
```

The `body` field is displayed in the UI; `metadata` is machine-readable context for the agent and is never shown to users.

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

Get recent messages for a channel with optional pagination.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `limit` | integer | no | Number of messages (default 20, max 200) |
| `since` | integer | no | Return only messages with id > since (message ID); useful for forward catch-up polling |
| `before` | integer | no | Return only messages with id < before; used for scroll-up pagination |

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

### GET /api/v1/channels/:channel_id/members

List members of a channel with their session and agent information.

**URL params:**

| Param | Type | Description |
|-------|------|-------------|
| `channel_id` | string | Channel ID |

**Response:** `200 OK`

```json
{
  "success": true,
  "channel_id": 1,
  "members": [
    {
      "session_id": 42,
      "session_uuid": "session-uuid",
      "session_name": "code-review",
      "agent_uuid": "agent-uuid",
      "role": "member",
      "joined_at": "2026-04-10T10:30:00Z"
    }
  ]
}
```

**Example:**

```bash
curl localhost:5001/api/v1/channels/1/members
eits channels members 1
```

---

### POST /api/v1/channels/:id/members

Add a member to a channel. On success, delivers an orientation DM to the joining agent with channel ID, key eits commands, and mention routing rules.

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

**Orientation DM:** The endpoint immediately starts a task to deliver a DM to the joining session containing:
- Channel name and ID
- Key channel commands (`eits channels messages`, `eits channels send`, `eits channels mine`)
- Mention routing rules (`@<session_id>`, `@all`, ambient messages)
- DM body ends with `[NO_RESPONSE]` so the agent does not auto-acknowledge

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
| `parent_session_id` | string or integer | no | Filter to child sessions of a given parent session (UUID or integer ID). Independent of other filters |
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
eits sessions list --parent 42
eits sessions list --parent abc-123-uuid
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

### GET /api/v1/teams

List teams with optional filtering by status and result limit.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | string | no | Filter by status: `"active"` (default, excludes archived), `"all"` (includes archived teams). Returns 400 on invalid input |
| `limit` | integer | no | Max results per page. Must be positive; returns 400 on negative or zero values |

**Response:** `200 OK`

```json
{
  "success": true,
  "teams": [
    {
      "id": 1,
      "name": "Platform Team",
      "description": "Core platform development",
      "created_at": "2026-04-10T10:00:00Z"
    }
  ]
}
```

**Example:**

```bash
curl 'localhost:5001/api/v1/teams?status=active&limit=20'
curl 'localhost:5001/api/v1/teams?status=all'
eits teams list
eits teams list --limit 50
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

### GET /api/v1/tasks

List tasks with optional filtering by project, session, agent, tag, search query, or time window.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `project_id` | integer | no | Filter to tasks in a specific project |
| `session_id` | string or integer | no | Filter to tasks for a specific session (UUID or integer ID) |
| `created_by_session_id` | string or integer | no | Filter to tasks created by a specific session |
| `agent_id` | string or integer | no | Filter to tasks assigned to an agent |
| `tag_id` | integer | no | Filter to tasks with a specific tag ID |
| `q` | string | no | Full-text search query (searches task titles, descriptions, body) |
| `state_id` | integer | no | Filter by workflow state ID |
| `since` | string | no | ISO 8601 datetime; returns tasks whose `updated_at` falls after this time |
| `stale_since` | string | no | ISO 8601 datetime; returns non-terminal tasks not updated since this cutoff |
| `limit` | integer | no | Max results (default 50) |

**Response:** `200 OK`

```json
{
  "success": true,
  "message": "2 task(s)",
  "tasks": [
    {
      "id": 1,
      "uuid": "task-uuid",
      "title": "Fix auth bug",
      "state": "In Progress",
      "state_id": 2,
      "description": "OAuth flow is broken",
      "project_id": 1,
      "priority": "high",
      "created_at": "2026-04-10T10:00:00Z",
      "updated_at": "2026-04-15T14:30:00Z"
    }
  ]
}
```

**Example:**

```bash
curl 'localhost:5001/api/v1/tasks?project_id=1&limit=20'
curl 'localhost:5001/api/v1/tasks?tag_id=1'
curl 'localhost:5001/api/v1/tasks?q=auth&state_id=2'
curl 'localhost:5001/api/v1/tasks?session_id=42'
curl 'localhost:5001/api/v1/tasks?since=2026-04-15T00:00:00Z'
curl 'localhost:5001/api/v1/tasks?stale_since=2026-04-10T00:00:00Z'
eits tasks list --project 1
eits tasks list --tag 5
```

---

### GET /api/v1/tasks/:id

Fetch a single task by ID. Read-only; no side effects.

**Path params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | integer | yes | Task ID |

**Response:** `200 OK`

```json
{
  "success": true,
  "id": 42,
  "title": "Fix auth bug",
  "project_id": 1,
  "state_id": 2,
  "task": {
    "id": 42,
    "title": "Fix auth bug",
    "description": "OAuth flow is broken in Safari",
    "state": "In Progress",
    "state_id": 2,
    "priority": "high",
    "due_at": null,
    "created_at": "2026-04-10T10:00:00Z",
    "updated_at": "2026-04-15T14:30:00Z"
  },
  "annotations": []
}
```

**Example:**

```bash
curl localhost:5001/api/v1/tasks/42
eits tasks get 42
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
      "description": "OAuth flow is broken",
      "created_at": "2026-04-10T10:00:00Z",
      "updated_at": "2026-04-15T14:30:00Z"
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

### GET /api/v1/tags

List all tags in the system with optional name search. Name search is pushed to the database query via ilike for efficient filtering.

**Query params:**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `q` | string | no | Filter tags by name (case-insensitive ilike substring match); pushed to DB query |

**Response:** `200 OK`

```json
{
  "success": true,
  "tags": [
    {
      "id": 1,
      "name": "bug"
    },
    {
      "id": 2,
      "name": "feature"
    }
  ]
}
```

**Example:**

```bash
curl localhost:5001/api/v1/tags
curl 'localhost:5001/api/v1/tags?q=bug'
eits tags list
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

## Rate limiting

All `/api/v1` requests pass through `EyeInTheSkyWeb.Plugs.RateLimit`.

**Phase 1:** IP-keyed buckets with orchestrator bypass.
- Default bucket is IP-keyed (`api:<ip>`).
- When `EITS_SESSION_UUID` is set, the `eits` CLI sends `x-eits-role: orchestrator` header to all curl requests, granting a 5× burst on a separate orchestrator bucket (`api:orch:<ip>`).
- This header is safe to send even when Phase 2 is disabled — the server ignores it if the per-session flag is off.

**Phase 2** (feature-flagged): Per-session bucketing. When `Settings.get_boolean("rate_limit_per_session")` is `true`:
- If the request includes a valid `x-eits-session: <uuid>` header that matches an existing session row, the bucket becomes `api:sess:<uuid>` with a 60-req/10s burst so co-located agents don't starve each other.
- If the flag is off, the header is missing, or the UUID is unknown, the plug falls back to Phase 1.
- The `eits` CLI always sends `x-eits-session` when `EITS_SESSION_UUID` is set.

**Telemetry:** Each rate-limit evaluation emits a `[:eits, :rate_limit, :check]` telemetry event with `%{remaining, limit}` and `%{bucket, session_id, bucket_kind, status}` metadata.

**Configuration:** Toggle the Phase 2 flag at `/settings` → **System** tab.
