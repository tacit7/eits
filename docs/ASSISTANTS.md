# Assistants

Reusable, configurable agent definitions that wrap a prompt with executable parameters — model, reasoning effort, tool policy, and scope. An assistant provides a repeatable identity for a class of agent work without hard-coding per-session configuration.

## Concepts

| Concept | What it is |
|---------|-----------|
| **Assistant** | A named configuration: prompt + model + tool policy + scope |
| **Tool catalog** | Global registry of available tools (`assistant_tools` table) |
| **Tool policy** | Per-assistant JSONB config controlling which tools are allowed, denied, or approval-gated |
| **Tool approval** | Execution hold: when a tool requires human sign-off, a `tool_approvals` record blocks the run until reviewed |
| **Memory** | Persistent notes scoped to an assistant, written during and after sessions |

---

## Database Schema

### `assistants` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer PK | Auto-generated |
| `name` | string (required) | Human-readable name |
| `prompt_id` | FK → `subagent_prompts` | System prompt content (nilified on prompt delete) |
| `model` | string | Default model (e.g. `claude-haiku-4-5-20251001`) |
| `reasoning_effort` | string | One of `low`, `medium`, `high` |
| `tool_policy` | jsonb | Per-assistant tool access rules (see below) |
| `default_trigger_type` | string | One of `manual`, `task_dispatch`, `schedule`, `api` |
| `project_id` | FK → `projects` | Scope to a project (nilified on project delete) |
| `team_id` | FK → `teams` | Scope to a team (nilified on team delete) |
| `active` | boolean | Soft-delete flag; false = excluded from queries |

### `assistant_tools` table (tool catalog)

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer PK | Auto-generated |
| `name` | string (unique) | Tool identifier used in policy rules |
| `description` | string | Human-readable description |
| `destructive` | boolean | True for side-effecting tools (UI badge) |
| `requires_approval_default` | boolean | True = approval required by default even for open-policy assistants |
| `active` | boolean | Soft-delete; inactive tools are excluded from policy checks |

#### Seeded tools

| Name | Destructive | Requires approval |
|------|-------------|------------------|
| `search_tasks` | no | no |
| `read_task` | no | no |
| `update_task` | no | no |
| `create_note` | no | no |
| `list_sessions` | no | no |
| `send_dm` | no | no |
| `post_channel_message` | no | no |
| `spawn_subagent` | no | no |
| `run_shell_command` | **yes** | **yes** |
| `write_file` | **yes** | **yes** |
| `search_project_files` | no | no |
| `create_task` | no | no |

### `tool_approvals` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer PK | Auto-generated |
| `session_id` | FK → `sessions` | Session that triggered the tool call |
| `assistant_id` | FK → `assistants` | Assistant that owns the policy |
| `tool_name` | string | Name of the tool being gated |
| `payload` | jsonb | Tool invocation arguments |
| `status` | string | One of `pending`, `approved`, `denied`, `expired` |
| `requested_by_type` | string | `"assistant"` or `"user"` |
| `requested_by_id` | string | Agent UUID or user ID of requester |
| `reviewed_by_id` | integer | User ID of the reviewer |
| `reviewed_at` | naive_datetime | When the review action was taken |
| `expires_at` | naive_datetime | Auto-expire time (default: 30 min from request) |

### Sessions fields added by assistant layer

| Column | Type | Description |
|--------|------|-------------|
| `assistant_id` | FK → `assistants` (nullable) | The assistant driving this session, if any |
| `trigger_type` | string (nullable) | How the session was initiated (`manual`, `task_dispatch`, `schedule`, `api`) |
| `run_context` | jsonb (nullable) | Caller-provided context passed at spawn time |

---

## Tool Policy

The `tool_policy` JSONB field on an assistant controls which tools it can use. Three lists are supported:

```json
{
  "allowed": ["search_tasks", "create_note"],
  "denied": ["run_shell_command"],
  "requires_approval": ["write_file", "spawn_subagent"]
}
```

### Precedence (evaluated in order)

1. Tool name in `denied` → `:denied`
2. Tool name in `requires_approval` → `:requires_approval`
3. Tool name in `allowed` → `:allowed`
4. `allowed` list is empty → open policy, fall through to tool catalog default
5. `allowed` list is non-empty and tool not in it → `:denied` (whitelist mode)
6. Tool's `requires_approval_default` is true → `:requires_approval` even under open policy

**Open policy**: an assistant with `tool_policy: nil` or `tool_policy: %{}` with an empty `allowed` list can use any active tool in the catalog (subject to `requires_approval_default` on individual tools).

---

## Tool Policy Enforcement (`ToolPolicy`)

Module: `EyeInTheSkyWeb.Assistants.ToolPolicy`

All tool invocations from assistant-driven sessions go through `ToolPolicy.authorize/5` before execution. The enforcement point is `SessionController.tool_event/2` — the `"pre"` branch calls `authorize` and returns 403 (denied) or 202 (pending approval) before recording or broadcasting anything.

```elixir
# Returns one of:
{:ok, :allowed}
{:ok, :requires_approval, %ToolApproval{}}
{:error, :tool_not_found}
{:error, :denied}
{:error, :assistant_not_found}   # assistant_id exists in session but record was deleted

ToolPolicy.authorize(session_id, assistant_id, tool_name, payload \\ %{}, opts \\ [])
```

Sessions without an `assistant_id` bypass policy entirely — ad hoc sessions are unconstrained.

**HTTP responses from `tool_event`**:

| Outcome | Status | Body |
|---------|--------|------|
| Allowed | 200 | `{success: true}` |
| Requires approval | 202 | `{status: "requires_approval", approval_id: <id>}` |
| Denied | 403 | `{status: "denied", message: "..."}` |
| Tool not found | 200 | Passes through (unknown tools are not blocked) |

---

## Approval Workflow

1. Tool invoked on a session with an assistant policy that gates the tool
2. `ToolPolicy.authorize` calls `enqueue_approval/5` — creates a `tool_approvals` record with `status: "pending"`
3. PubSub event `{:approval_requested, approval}` broadcast on `"tool_approvals"` topic via `Events.tool_approval_requested/1`
4. The HTTP request that triggered the tool returns 202; the Claude CLI receives the response and must pause
5. Reviewer sees the request in `/approvals` (real-time via LiveView)
6. Reviewer clicks Approve or Deny → `ToolPolicy.approve/2` or `ToolPolicy.deny/2`
7. `{:approval_updated, approval}` broadcast via `Events.tool_approval_updated/1`
8. Stale pending approvals can be force-expired with `ToolPolicy.expire_stale/0` (runs via the "Expire stale" button in the UI, or a scheduled job)

### Approval inbox (`/approvals`)

LiveView: `EyeInTheSkyWebWeb.OverviewLive.Approvals`

- Filter tabs: Pending / Approved / Denied / All
- Real-time updates via `Events.subscribe_tool_approvals/0`
- Payload expandable via `<details>`
- Destructive tools highlighted in red (currently: `run_shell_command`, `write_file`)

---

## Memory Layer

Module: `EyeInTheSkyWeb.Assistants.Memory`

No new tables. Memory is stored as notes with `parent_type: "assistant"` and `parent_id: to_string(assistant_id)`.

### Memory kinds

| Kind | When to write |
|------|--------------|
| `summary` | End of session — rolling narrative of what happened |
| `preference` | How the assistant should behave (tone, output format, etc.) |
| `convention` | Project conventions discovered during work |
| `decision` | Significant decisions made during a run |
| `blocker` | Recurring obstacles or known failure modes |
| `context` | Project/domain background the assistant should retain |

### Note title format

```
[kind] optional label
```

Examples:
- `[summary] session 1150`
- `[convention] naming`
- `[decision] memory system`

### Session linkage

When `session_id` is provided to `Memory.write/3`, the body is prefixed with:

```
session_id: <id>

<actual content>
```

This allows `Memory.list/2` to filter by originating session via SQL `LIKE`.

### API

```elixir
# Write a memory note
Memory.write(assistant, body, kind: :convention, label: "naming")
Memory.write(assistant, body, kind: :summary, session_id: 1150)

# Write a session summary (shorthand)
Memory.write_session_summary(assistant, session_id, body)

# List memory notes
Memory.list(assistant, kind: :convention, limit: 10)
Memory.list(assistant, session_id: 1150)

# Get most recent of a kind
Memory.latest(assistant, :summary)

# Full-text search
Memory.search(assistant, "snake_case naming")

# Build a prompt injection block
Memory.build_context(assistant)
# Returns: "## Assistant Memory\n\n**Conventions**\n- ..."
```

---

## Spawning an Assistant-Driven Session

Pass `assistant_id` to `POST /api/v1/spawn`:

```bash
curl -X POST http://localhost:5001/api/v1/spawn \
  -H "Content-Type: application/json" \
  -d '{
    "assistant_id": 1,
    "trigger_type": "api",
    "run_context": {"task_id": 42}
  }'
```

The `AgentController.resolve_assistant/1` plug runs before `validate_params/1`. It:

1. Loads the assistant record (returns 404 if not found)
2. Sets `instructions` from the assistant's prompt text (caller can override)
3. Sets `model` from the assistant's model field (caller can override)
4. Sets `effort_level` from `reasoning_effort` (caller can override)
5. Sets `trigger_type` default from `assistant.default_trigger_type` (caller can override)
6. Merges `assistant_id` into the params map

These values flow into the session record: `assistant_id`, `trigger_type`, `run_context`.

---

## Context Module (`EyeInTheSkyWeb.Assistants`)

```elixir
# CRUD
Assistants.list_assistants(project_id: id, include_inactive: false)
Assistants.list_project_assistants(project_id)
Assistants.list_global_assistants()
Assistants.get_assistant(id)       # returns nil if not found
Assistants.get_assistant!(id)      # raises if not found
Assistants.create_assistant(attrs)
Assistants.update_assistant(assistant, attrs)
Assistants.deactivate_assistant(assistant)  # soft delete
Assistants.delete_assistant(assistant)      # hard delete

# Tool registry
Assistants.list_tools(include_inactive: false)
Assistants.get_tool_by_name(name)     # returns nil if not found
Assistants.check_tool_policy(assistant, tool_name)
# → {:ok, :allowed} | {:ok, :requires_approval} | {:error, :denied}
Assistants.allowed_tool_names(assistant)
# → ["search_tasks", "create_note", ...]  (excludes denied, respects whitelist mode)
```

---

## PubSub Events

All published via `EyeInTheSkyWeb.Events`. Topic: `"tool_approvals"`.

| Function | Payload | When |
|----------|---------|------|
| `Events.tool_approval_requested/1` | `{:approval_requested, approval}` | New approval record created |
| `Events.tool_approval_updated/1` | `{:approval_updated, approval}` | Approval approved, denied, or expired |
| `Events.subscribe_tool_approvals/0` | — | Subscribe to the `"tool_approvals"` topic |

---

## Migrations

| File | Description |
|------|-------------|
| `20260317012652_create_assistants.exs` | Creates `assistants` table |
| `20260317013928_add_assistant_fields_to_sessions.exs` | Adds `assistant_id`, `trigger_type`, `run_context` to `sessions` |
| `20260317014905_create_tools.exs` | Creates `assistant_tools` table, seeds 12 tools |
| `20260317015310_create_tool_approvals.exs` | Creates `tool_approvals` table |
| `20260317061528_add_team_id_fk_to_assistants.exs` | Adds FK constraint on `assistants.team_id` → `teams` |

---

## File Map

```
lib/eye_in_the_sky_web/
  assistants.ex                      # Context: CRUD + tool registry + policy check
  assistants/
    assistant.ex                     # Schema: assistants table
    tool.ex                          # Schema: assistant_tools table
    tool_approval.ex                 # Schema: tool_approvals table
    tool_policy.ex                   # Policy engine: authorize/5, approve/2, deny/2
    memory.ex                        # Memory layer on top of notes

lib/eye_in_the_sky_web_web/
  controllers/api/v1/
    agent_controller.ex              # resolve_assistant/1 plug; spawns assistant-driven sessions
    session_controller.ex            # tool_event/2: policy enforcement on "pre" events
  live/overview_live/
    approvals.ex                     # /approvals — real-time approval inbox LiveView
```
