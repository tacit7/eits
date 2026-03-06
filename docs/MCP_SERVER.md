# EITS MCP Server

Streamable HTTP MCP server served at `POST /mcp`. Built with [Anubis](https://hex.pm/packages/anubis_mcp).

**Server name:** `eye-in-the-sky` | **Version:** `1.0.0` | **Capabilities:** `tools`

Tool names are prefixed `mcp__eye-in-the-sky__*`. A Go binary fallback (`eits-go`) exposes the same surface.

All tools return a JSON response with at minimum `success: boolean`. Errors include a `message` field. All UUIDs are string-format session UUIDs — the server resolves them to integer IDs internally.

---

## Session Tools

### `i-session`

Multi-command session lifecycle tool.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `command` | string | **yes** | `start`, `end`, `update`, `info`, `search`, `save-context`, `load-context` |
| `session_id` | string | — | Claude Code session UUID (required for `start`) |
| `agent_id` | string | — | Agent UUID (alias for `session_id` on some commands) |
| `name` | string | — | Human-readable session name |
| `description` | string | — | What you're working on |
| `agent_description` | string | — | Agent label (e.g. `"Frontend Dev Agent"`) |
| `project_name` | string | — | Project name |
| `worktree_path` | string | — | Path to git worktree |
| `model` | string | — | Model ID (e.g. `claude-sonnet-4-5-20250929`) |
| `provider` | string | — | AI provider (default: `claude`) |
| `parent_agent_id` | string | — | Parent agent UUID for subagents |
| `parent_session_id` | string | — | Parent session UUID for subsessions |
| `persona_id` | string | — | Persona ID to preload context from |
| `status` | string | — | Session status (for `update`) |
| `summary` | string | — | Work summary (for `end`) |
| `final_status` | string | — | `completed` or `failed` (for `end`, default: `completed`) |
| `query` | string | — | Search query (for `search`) |
| `context` | string | — | Markdown context (for `save-context`) |
| `limit` | integer | — | Max results (default: 20) |

**Commands:**

- **`start`** — Creates or finds an existing session by UUID. Returns `session_id`, `agent_id`, `session_int_id`. Note: does not update `name` on existing sessions; use `update` for that.
- **`end`** — Sets `ended_at` on the session.
- **`update`** — Updates `name`, `status`, or `description`.
- **`info`** — Returns current session state and `initialized` flag.
- **`search`** — FTS5 search over sessions by name/description.
- **`save-context`** / **`load-context`** — Persist/retrieve markdown context for a session.

---

### `i-session-info`

Fetch session state by UUID without the full multi-command surface.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | — | Session UUID to look up |

Returns `agent_id`, `session_id`, `project_id`, `status`, `initialized`.

---

### `i-end-session`

Mark a session complete. Sets `ended_at` timestamp.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | **yes** | Session UUID |
| `summary` | string | — | Summary of work completed |
| `final_status` | string | — | `completed` or `failed` (default: `completed`) |

---

### `i-session-search`

Full-text search over sessions using FTS5. Falls back to LIKE on error.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `query` | string | **yes** | Search query |
| `limit` | integer | — | Max results (default: 20) |

Returns `success`, `message`, `results[]` with `id`, `uuid`, `description`, `status`.

---

## Note Tools

### `i-note-add`

Create a note attached to any entity.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `parent_id` | string | **yes** | ID of the parent entity |
| `parent_type` | string | **yes** | `session`, `task`, or `agent` |
| `body` | string | **yes** | Note content |
| `title` | string | — | Optional title |
| `starred` | integer | — | `0` or `1` (default: `0`) |

Returns `success`, `message`, `id` (integer PK of created note).

---

### `i-note-get`

Retrieve a single note by its integer ID.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `note_id` | string | **yes** | Note integer ID (as string) |

Returns `note_id`, `parent_id`, `parent_type`, `title`, `body`, `starred`, `created_at`.

---

### `i-note-search`

Full-text search over notes using FTS5.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `query` | string | **yes** | Search query |
| `limit` | integer | — | Max results (default: 20) |

Returns `success`, `results[]` with `id`, `body`, `title`, `parent_id`, `parent_type`.

---

## Task Tool

### `i-todo`

Multi-command task management tool. All task IDs are the integer PK as a string.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `command` | string | **yes** | See commands below |
| `task_id` | string | — | Task integer ID (as string) |
| `title` | string | — | Task title (for `create`) |
| `description` | string | — | Task description |
| `priority` | integer | — | Priority level |
| `state_id` | integer | — | Workflow state ID (1=Todo, 2=In Progress, 4=In Review, 3=Done) |
| `project_id` | integer | — | Project ID |
| `agent_id` | string | — | Agent UUID |
| `session_id` | string | — | Session UUID |
| `query` | string | — | Search query |
| `tags` | list[string] | — | Tags to add |
| `body` | string | — | Note body (for `annotate`) |
| `due_at` | string | — | Due date (ISO 8601) |
| `limit` | integer | — | Result limit |

**Commands:**

| Command | Description |
|---------|-------------|
| `create` | Create a task. Returns `task_id`. |
| `start` | Move task to In Progress state. |
| `done` | Mark task complete (moves to Done state). |
| `status` | Update task `state_id`. |
| `delete` | Delete a task. |
| `annotate` | Add a note to a task. |
| `list` | List all tasks. |
| `list-agent` | List tasks by agent UUID. |
| `list-session` | List tasks by session UUID. |
| `search` | FTS5 search over task title/description. |
| `tag` | Add tags to a task. |
| `add-session` | Associate a session with a task. |
| `remove-session` | Dissociate a session from a task. |

---

## Data Tools

### `i-commits`

Log git commits against a session. Commits require a valid session to link to.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | **yes** | Session UUID |
| `commit_hashes` | list[string] | **yes** | Git commit hashes |
| `commit_messages` | list[string] | — | Commit messages (parallel array to hashes) |

Returns `success`, `message` with count (e.g. `"Logged 2/2 commits"`). Unknown session UUIDs result in 0 logged (session_id required on DB row).

---

### `i-prompt-get`

Retrieve a subagent prompt template. Provide either `id` or `slug`.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | — | Prompt integer ID |
| `slug` | string | — | Prompt slug |
| `project_id` | string | — | Project context for scoped slug lookup |
| `include_text` | boolean | — | Include `prompt_text` in response (default: `true`) |

Returns `success`, `prompt` object with `id`, `slug`, `name`, and optionally `prompt_text`.

---

### `i-project-add`

Create a project for tracking agents and tasks.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | **yes** | Project name |
| `slug` | string | — | URL-friendly slug |
| `path` | string | — | Local filesystem path |
| `remote_url` | string | — | Git remote URL |
| `git_remote` | string | — | Git remote name (e.g. `origin`) |
| `repo_url` | string | — | Repository URL |
| `branch` | string | — | Git branch |
| `active` | boolean | — | Active status (default: `true`) |

Returns `success`, `message`, `project_id`.

---

### `i-save-session-context`

Persist markdown context for a session. Resolves the session UUID to integer IDs before writing.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | **yes** | Session UUID |
| `session_id` | string | — | Session UUID (takes priority over `agent_id` if provided) |
| `context` | string | **yes** | Markdown content |

---

### `i-load-session-context`

Load the latest saved context for a session.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `agent_id` | string | **yes** | Session UUID |
| `session_id` | string | — | Session UUID (takes priority over `agent_id` if provided) |

Returns `success`, `context`, `created_at`, `updated_at`.

---

## System Tools

### `i-speak`

macOS text-to-speech. No-op on non-macOS.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `message` | string | **yes** | Text to speak |
| `voice` | string | — | `Ava` (default), `Isha`, `Lee`, `Jamie`, `Serena` |
| `rate` | integer | — | Words per minute (90–450, default: 200) |

---

### `i-window`

Get the currently active macOS window and application name.

No parameters required.

---

## Messaging Tools

### `i-nats-send`

Publish a message to the local NATS JetStream. Subject is auto-prefixed with `events.` if not present.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `sender_id` | string | **yes** | Your session UUID |
| `message` | string | **yes** | Message content |
| `receiver_id` | string | — | Target session UUID. Empty = broadcast |
| `subject` | string | — | Message subject |

---

### `i-nats-listen`

Poll for new NATS messages in the instruction queue for this session.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `session_id` | string | **yes** | Your session UUID |
| `last_sequence` | integer | — | Last processed sequence number for pagination |
| `max_messages` | integer | — | Messages to fetch (default: 10) |

---

### `i-nats-send-remote`

Publish a message to a remote NATS server.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `server_url` | string | **yes** | Remote NATS server URL |
| `sender_id` | string | **yes** | Your session UUID |
| `message` | string | **yes** | Message content |
| `receiver_id` | string | — | Target session UUID. Empty = broadcast |
| `subject` | string | — | Message subject |

---

### `i-nats-listen-remote`

Poll for messages from a remote NATS server.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `server_url` | string | **yes** | Remote NATS server URL |
| `session_id` | string | **yes** | Your session UUID |
| `last_sequence` | integer | — | Last processed sequence number |
| `max_messages` | integer | — | Messages to fetch (default: 10) |

---

### `i-chat-send`

Send a message to a chat channel. Resolves session UUID to integer ID before writing. Broadcasts `{:new_message, msg}` on `channel:{channel_id}:messages`.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `channel_id` | string | **yes** | Channel integer ID |
| `session_id` | string | **yes** | Sender session UUID |
| `body` | string | **yes** | Message body |
| `sender_role` | string | — | Default: `agent` |
| `recipient_role` | string | — | Default: `user` |
| `provider` | string | — | Default: `claude` |

Returns `success`, `message`, `message_id`.

---

### `i-chat-channel-list`

List available chat channels.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `project_id` | integer | — | Filter by project |

Returns `success`, `channels[]` with `id`, `name`, `channel_type`, `project_id`.

---

### `i-dm`

Send a direct message to another agent's session. Stored as an inbound message and broadcasts `{:new_dm, msg}` on `session:{int_id}`.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `sender_id` | string | **yes** | Your session UUID |
| `target_session_id` | string | **yes** | Target session UUID |
| `message` | string | **yes** | Message body |
| `response_required` | boolean | — | Default: `false` |

---

## Agent Spawning Tools

### `i-spawn-agent`

Spawn a new Claude Code agent with EITS tracking. Registers agent and session in the DB.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `instructions` | string | **yes** | Task instructions |
| `model` | string | — | `haiku`, `sonnet`, `opus` (default: `haiku`) |
| `project_path` | string | — | Working directory (default: current) |
| `skip_permissions` | boolean | — | Skip permission prompts (default: `true`) |
| `background` | boolean | — | Run in background (default: `false`) |
| `parent_agent_id` | string | — | Parent agent UUID |
| `parent_session_id` | string | — | Parent session UUID |

---

### `i-spawn-claude`

Spawn a bare Claude Code process and capture its session UUID from the init message.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `prompt` | string | **yes** | Prompt to send |
| `model` | string | **yes** | Model ID (`haiku`, `sonnet`, `opus`, or full ID) |
| `project_path` | string | — | Working directory |

---

## Architecture Notes

- **Transport:** Streamable HTTP at `POST /mcp` via [Anubis](https://hex.pm/packages/anubis_mcp).
- **Server name:** `eye-in-the-sky` in `~/.claude/settings.json`. Tool names are `mcp__eye-in-the-sky__*`. Go binary fallback is registered as `eits-go` (`mcp__eits-go__*`).
- **Validation:** All input is validated by [Peri](https://hex.pm/packages/peri); parameters arrive as atom-keyed maps in `execute/2`.
- **UUID resolution:** Tools that take session UUIDs resolve them to integer PKs internally via `Sessions.get_session_by_uuid/1` before any DB writes.
- **PubSub:** Messaging tools broadcast on `session:{id}` and `channel:{id}:messages` topics for LiveView subscriptions.
- **FTS5:** Search tools use FTS5 virtual tables (`sessions_fts`, `notes_fts`, `task_search`) with LIKE fallback on parse errors.
- **CLI output parsing:** The `Parser` module skips non-JSON lines and surfaces plain-text `Error:` lines from the CLI as `{:error, {:cli_error, line}}` rather than crashing on JSON decode.
- **No migrations:** The Phoenix app never writes schema changes. All table definitions are owned by the Go core (`schema.sql`).
