# REST API v1

Base URL: `http://localhost:4000/api/v1`

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
  "agent_id": 7,
  "chat_agent_uuid": "agent-uuid",
  "status": "working"
}
```

**Example:**

```bash
curl -X POST localhost:4000/api/v1/sessions \
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
curl -X PATCH localhost:4000/api/v1/sessions/abc-123 \
  -H 'Content-Type: application/json' \
  -d '{"status":"completed"}'
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
curl -X POST localhost:4000/api/v1/commits \
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
curl -X POST localhost:4000/api/v1/notes \
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
curl -X POST localhost:4000/api/v1/session-context \
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
