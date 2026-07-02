# Claude Session Management Architecture

The Eye in the Sky web application spawns Claude Code CLI subprocesses to handle DM conversations, agent sessions, and project-scoped prompts. Session management uses a DynamicSupervisor pattern for per-session process isolation.

---

## Sessions Context Architecture

The Sessions context (`lib/eye_in_the_sky/sessions/`) has been refactored into focused sub-modules for better separation of concerns:

### Module Organization

The main `Sessions` module now acts as a facade, delegating to three specialized sub-modules while maintaining the same public API:

| Module | Responsibility | Functions |
|--------|---|---|
| **`Sessions.Query`** | Read-only session retrieval and queries | `list_sessions/1`, `get_session/1`, `list_active_sessions/0`, `get_session_by_uuid/1`, `list_sessions_for_agent/2`, `list_project_sessions_with_agent/2`, `count_and_ids_for_project/1`, etc. |
| **`Sessions.StatusTransitions`** | State-changing operations and transitions | `set_session_idle/1`, `end_session/2`, `archive_session/1`, `unarchive_session/1`, `update_session/2`, `batch_delete_sessions/1` |
| **`Sessions.OverviewQueries`** | Complex/aggregated queries for the overview page | `list_sessions_for_scope/1`, `count_sessions_by_status/1`, etc. (file: `sessions/queries.ex`) |
| **`Sessions.Events`** | PubSub event broadcasting (implementations inline, no BroadcastEvents delegate) | `broadcast_session_updated/1`, `broadcast_session_completed/1`, `broadcast_session_waiting/1`, `broadcast_status_side_effects/2` |
| **`Sessions`** (facade) | Unified public API and delegation | Delegates to Query, StatusTransitions, and Events; maintains backward compatibility |

### Design Rationale

- **Query isolation:** All read operations are co-located in `Sessions.Query`, making it easy to identify and optimize slow queries
- **State changes:** All mutations go through `Sessions.StatusTransitions`, centralizing side effects and making transition logic discoverable
- **Event broadcasting:** Broadcasting logic is separated from CRUD, keeping the Sessions context boundary clear (data changes in StatusTransitions, events in Sessions.Events)
- **Facade pattern:** The main `Sessions` module delegates via `defdelegate`, preserving the original public API — callers don't need to know about the sub-modules
- **No API breakage:** All existing function calls to `Sessions.*` continue to work unchanged

### Example Delegation

From the main `Sessions` module:

```elixir
# Query delegation
defdelegate list_sessions(opts), to: Query
defdelegate get_session(id), to: Query
defdelegate list_sessions_for_agent(agent_id, opts), to: Query

# Status transition delegation
defdelegate set_session_idle(session), to: StatusTransitions
defdelegate end_session(session, opts), to: StatusTransitions
defdelegate archive_session(session), to: StatusTransitions
defdelegate update_session(session, attrs), to: StatusTransitions

# Event delegation
defdelegate broadcast_session_updated(session), to: Events
defdelegate broadcast_session_completed(session), to: Events
```

---

## Architecture Overview

```
SessionManager (GenServer)              -- thin coordinator, no state
    |
    +-- creates ref, calls DynamicSupervisor.start_child
    |
    v
SessionSupervisor (DynamicSupervisor)   -- restart: :one_for_one
    |
    +-- SessionWorker (GenServer)        -- restart: :temporary
    |       |
    |       +-- handler (spawn_link)     -- reads port, sends messages to worker
    |       |
    |       +-- Port (claude CLI)        -- owned by handler
    |
    +-- SessionWorker
    |       +-- handler
    |       +-- Port
    |
    +-- ...

Registry (keys: :duplicate)             -- O(1) lookup by ref or session_id
```

## Components

### SessionManager (`lib/eye_in_the_sky_web/claude/session_manager.ex`)

Stateless coordinator. Creates a `session_ref`, starts a SessionWorker under DynamicSupervisor, returns the ref to the caller. All client API signatures are unchanged from the previous monolithic implementation.

**Client API:**

| Function | Purpose |
|---|---|
| `start_session(session_id, prompt, opts)` | New Claude session |
| `continue_session(session_id, prompt, opts)` | Continue existing session (`-c` flag) |
| `resume_session(session_id, prompt, opts)` | Resume by UUID (`--resume` flag) |
| `cancel_session(session_ref)` | Kill a running session by ref |
| `list_sessions()` | List all active workers |

SessionManager holds no state. It exists as a named GenServer purely for API consistency with callers. It could be replaced with a plain module.

### SessionWorker (`lib/eye_in_the_sky_web/claude/session_worker.ex`)

One GenServer per Claude CLI session. Owns the port lifecycle, parses JSON output, records messages to the database, and broadcasts via PubSub.

**Child spec:** `restart: :temporary` because sessions are transient; a crashed session should not auto-restart.

**Init flow:**
1. Receives `%{spawn_type, session_id, prompt, opts}` with a pre-created `session_ref`
2. Registers in Registry under `{:ref, session_ref}` and `{:session, session_id}`
3. Sets `:caller` to `self()` so the port handler links to this worker
4. Calls the appropriate `CLI.spawn_*` function
5. Stores port, session_id, ref, timestamps, output buffer in state

**Message handling:**
- `{:claude_output, ref, line}` -- JSON decode, extract text, record message async via TaskSupervisor, broadcast `{:claude_response, ref, parsed}` on `"session:<session_id>"`
- `{:claude_exit, ref, exit_code}` -- broadcast `{:claude_complete, ref, exit_code}`, stop with `:normal`
- `terminate/2` -- closes port if still open (defense-in-depth)

### CLI (`lib/eye_in_the_sky_web/claude/cli.ex`)

Spawns the actual `claude` binary as a port. Accepts `:session_ref` in opts so the ref is consistent end-to-end. If not provided, falls back to `make_ref()` for backward compatibility.

The port handler process is `spawn_link`ed from within CLI. In the DynamicSupervisor setup, the caller is always the SessionWorker, so the link chain is: Worker <-> Handler <-> Port.

### Effort Level Handling

When spawning Claude sessions, the system can optionally pass an `effort_level` parameter that controls the reasoning depth for the Claude model. The effort level is passed to the Claude CLI via the `--effort` flag.

**Effort Level Contract:**

The `effort_level` parameter can be:
- A specific level string: `"low"`, `"medium"`, `"high"`, `"xhigh"`, or `"max"` — these are passed to the CLI as `--effort <level>`
- An empty string `""` — no `--effort` flag is sent
- The string `"auto"` — no `--effort` flag is sent; the CLI decides the effort level

**Key behavior:** When `effort_level` is `"auto"`, the `--effort` flag is **not** passed to the Claude CLI. This means the CLI uses its default reasoning behavior without explicit direction from the caller.

**Implementation** in `lib/eye_in_the_sky_web/live/shared/session_helpers.ex`:
```elixir
[model: model]
|> then(fn opts ->
  if is_binary(effort_level) and effort_level not in ["", "auto"],
    do: Keyword.put(opts, :effort_level, effort_level),
    else: opts
end)
```

The condition filters out both empty strings and `"auto"`, ensuring neither generates a `--effort` flag in the spawned process arguments.

**Previous behavior (buggy):** The condition previously only filtered empty strings (`effort_level != ""`). Selecting "Auto" in the UI would emit `--effort auto`, which the Claude CLI does not accept as a valid level, causing session spawn failures.

**Result:** Users can now select "Auto" (or `"auto"` programmatically) to let the Claude CLI determine reasoning depth automatically, without forcing a specific level.

### Registry (`EyeInTheSkyWeb.Claude.Registry`)

Elixir Registry with `keys: :duplicate`. Each worker registers under two keys:

| Key | Purpose |
|---|---|
| `{:ref, session_ref}` | Cancel lookups (ref is what callers store in socket assigns) |
| `{:session, session_id}` | Session-based lookups (e.g., finding worker for a given session) |

Duplicate keys are required because multiple workers can exist for the same `session_id` (e.g., a resume creates a new worker while the old one is still shutting down). Registry entries are automatically removed when the owning process dies.

## Crash Isolation

The previous design had a single SessionManager GenServer holding all ports in a map. One port handler crash would take down the manager and kill every active session.

The new design isolates each session:

| Failure | Impact |
|---|---|
| Handler crash | Linked worker dies, `terminate/2` closes port. Other sessions unaffected. |
| Worker killed | Linked handler dies, port closes when owner dies. Other sessions unaffected. |
| SessionManager crash | Workers are under DynamicSupervisor, not SessionManager. Sessions continue. |
| DynamicSupervisor crash | Restarted by top-level supervisor. Active workers die, but this is catastrophic-level failure. |

## Supervision Tree

```elixir
# application.ex children (order matters)
{Task.Supervisor, name: EyeInTheSkyWeb.TaskSupervisor},
{Registry, keys: :duplicate, name: EyeInTheSkyWeb.Claude.Registry},
{DynamicSupervisor, name: EyeInTheSkyWeb.Claude.SessionSupervisor, strategy: :one_for_one},
EyeInTheSkyWeb.Claude.SessionManager,
```

Registry and DynamicSupervisor must start before SessionManager. TaskSupervisor must start before any workers since they use it for async message recording.

## PubSub Contract

Unchanged from the previous implementation. LiveViews subscribe to `"session:<session_id>"` and receive:

| Message | When |
|---|---|
| `{:claude_response, session_ref, parsed_json}` | Each parsed JSON line from Claude |
| `{:claude_complete, session_ref, exit_code}` | Claude process exited |

All 11 call sites across `dm_live.ex`, `agent_live/`, `project_live/`, and `chat_live.ex` remain untouched.

## Channel Agents

`spawn_channel_agent` in CLI runs outside this supervision tree. Channel agents are spawned directly by LiveViews via `Task.Supervisor.start_child` with their own output handler (`handle_channel_output`). They have a different lifecycle and message routing (channel-based, not session-based). Integration into the DynamicSupervisor pattern is a future option.

### Channel Session Read Receipts

When an agent produces a result in a channel context, the system marks the agent's session as having consumed messages up to that point via `Channels.mark_as_read`. This is handled in `AgentWorkerEvents.on_result_received/3` via the `maybe_mark_channel_read/2` helper:

**Behavior:**
- Called after each agent reply (result_received event)
- No-op when `channel_id` is nil (DM path)
- No-op when session is not a channel member (update_all affects zero rows)
- Synchronous in test mode (`async_tasks_sync: true`); runs in supervised `TaskSupervisor` in production
- Writes `last_read_at` timestamp to the channel member record, marking the session as having consumed all messages up to that point

**Implementation:**
```elixir
defp maybe_mark_channel_read(nil, _session_id), do: :ok

defp maybe_mark_channel_read(channel_id, session_id) do
  if Application.get_env(:eye_in_the_sky, :async_tasks_sync, false) do
    Channels.mark_as_read(channel_id, session_id)
  else
    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      Channels.mark_as_read(channel_id, session_id)
    end)
  end
  :ok
end
```

This allows the UI to show which agent sessions in a channel have read which messages, supporting read-receipts and user-facing "seen" indicators.

## Agent State Lifecycle

Agent state is independent from session state and transitions through three states during the agent spawning and execution lifecycle:

| State | Transition | Meaning |
|---|---|---|
| `:pending` | On :queued or :retry_queued admission | Agent is queued for spawning, worker process not yet running |
| `:running` | On SDK :started event | CLI process started, agent actively processing |
| `:failed` | On dispatch error or spawn failure | Agent spawn failed or Claude SDK error during execution |

**Key mechanics:**
- `promote_agent_if_pending/1` transitions an agent from pending → running when SDK successfully starts
- This promotion is **synchronous** (not Task.start) to ensure completion before next event fires — critical for test sandbox safety
- Failed agents remain in `:failed` state; no auto-recovery without explicit retry

---

## Team Member Status & Spawn Failures

Team members track two independent status fields:

| Field | Values | Set By | Purpose |
|-------|--------|--------|---------|
| `member_status` | `active`, `done`, `spawn_failed`, `idle` | Team/Tasks APIs | Team membership state; **authoritative for orchestrators** |
| `session_status` | `working`, `idle`, `waiting`, `completed`, `failed` | Lifecycle hooks | Claude process lifecycle; may lag behind member_status |

**Key behavior:**
- **`member_status: done`** fires immediately when `eits tasks complete` is called, not when the session ends
- **`session_status`** reflects the Claude Code process and lags — a member can be done but still show `working`
- **Orchestrators should check `member_status`**, not `session_status`

### Terminated Statuses

Terminated statuses (sessions that can no longer send or receive messages) are centralized in the `Sessions` module via the `terminated_statuses/0` function:

```elixir
Sessions.terminated_statuses()  # Returns ~w(completed failed)
```

This function is used across the messaging and team controllers to check whether a session is in a terminal state. Previously, this list was duplicated in multiple controllers; it is now centralized to maintain consistency.

### Spawn Failures

When `eits agents spawn` fails (non-2xx response), the system records a team member with `member_status: spawn_failed`:

**Flow:**
1. `AgentManager.spawn_agent/2` encounters an error creating the agent
2. Calls `SpawnTeamContext.record_spawn_failure(team, member_name)` 
3. Inserts a member row with `status: "spawn_failed"` (no linked session or agent)
4. Error is logged to `EITS_SPAWN_LOG` (default: `~/.eits/spawn-errors.log`) and echoed to stderr
5. `eits teams status --summary` counts and displays spawn_failed members

**Implementation** in `SpawnTeamContext.record_spawn_failure/2`:
```elixir
def record_spawn_failure(nil, _member_name), do: :ok

def record_spawn_failure(team, member_name) do
  name = member_name || "unknown-#{System.unique_integer([:positive])}"
  Teams.join_team(%{
    team_id: team.id,
    name: name,
    role: "member",
    status: "spawn_failed"
  })
end
```

**Spawn log output** (`EITS_SPAWN_LOG`):
```
2026-04-21T02:34:07Z rc=1 cmd=agents/spawn spawn error: connection refused
```

This allows orchestrators to detect and recover from spawn failures without monitoring session status.

---

## Session Status Lifecycle

Session status is set by lifecycle hooks and reflects the CLI process state:

| Status | Set By | Meaning |
|---|---|---|
| `working` | UserPromptSubmit hook | Claude Code is processing a message |
| `idle` | Stop hook, SessionEnd hook (cli), or SessionEnd hook (sdk-cli) | Session stopped gracefully; sdk-cli can be resumed |
| `waiting` | Explicit POST /sessions/:id/waiting | Session waiting for action/resume; blocked or temporarily paused |
| `completed` | Explicit POST /sessions/:id/complete or i-end-session skill | Session finished (manually set) |
| `failed` | AgentWorker abnormal exit or zombie sweep | Billing/auth/watchdog error, agent crash, or zombie cleanup; session persisted to DB, Teams cleanup fired |

### Status Reason Field

The `status_reason` field (`:string`) stores context for a session's status, particularly the `waiting` state. It is auto-cleared when a session transitions away from `waiting`:

```elixir
# In SessionController.build_update_attrs/2:
attrs =
  if status && status != "waiting" && !params["status_reason"] do
    Map.put(attrs, :status_reason, nil)
  else
    attrs
  end
```

**Common values:**
- `"session_ended"` — Set by eits-session-end.sh (sdk-cli SessionEnd hook) when transitioning to `idle`
- `"sdk_completed"` — Set when Codex agent completes (no longer parks in waiting; now transitions to `idle`)
- `"zombie_swept"` — Set by zombie sweep scheduler when marking stuck sessions as failed
- Custom reasons — Set explicitly via `/sessions/:id/waiting` endpoint

**Example use cases:**
- `idle` + `status_reason: "session_ended"` — sdk-cli session paused; can be resumed with --resume
- `waiting` + `status_reason: "awaiting resume signal"` — custom pause state (explicit, not automatic)
- Transitioning to `working` with no explicit reason clears the field automatically
- Explicit `status_reason` in a transition (e.g., `status: "waiting"` + `status_reason: "custom reason"`) is preserved

Set via `PATCH /api/v1/sessions/:uuid` with `status_reason` parameter, or use explicit endpoints:
- `POST /api/v1/sessions/:uuid/waiting` — Set status to waiting with optional reason
- `POST /api/v1/sessions/:uuid/complete` — Set status to completed and sync team member

**Systemic Error Handling:**
When AgentWorker encounters a systemic error (billing failure, auth error, watchdog timeout, or abnormal termination), it calls `AgentWorkerEvents.on_session_failed/3` with the classified reason:
1. Streams error event to session channel
2. Overwrites session status in DB to `"failed"` and persists the category to `status_reason` (one of `"billing_error"`, `"authentication_error"`, `"watchdog_timeout"`, `"retry_exhausted"`, or `nil` for unclassified crashes)
3. The LiveView badge layer (`StatusHelpers.derive_display_status/2`) branches on `status_reason` to render distinct red tiers — `failed_billing`, `failed_auth`, `failed_rate_limit`, `failed_timeout`, `failed_retry_exhausted` — instead of collapsing into a generic "Failed"

**Rate-limit note:** `rate_limit_error` is classified so the UI can distinguish it, but is NOT systemic — `RetryPolicy` keeps retrying 429s with exponential backoff. Only after max retries exhaust does the session move to `failed` with `status_reason: "retry_exhausted"`.

Implementation in `on_session_failed/3`:

```elixir
def on_session_failed(session_id, provider_conversation_id, reason) do
  Events.stream_error(session_id, provider_conversation_id, "Systemic error — session failed")
  update_session_status(session_id, "failed", ErrorClassifier.status_reason(reason))
  :ok
end
```

**Zombie Session Sweep:**
The AgentStatus scheduler includes a zombie sweep that marks sessions stuck in `working` status for >30 minutes with no heartbeat as `failed`:
- Runs periodically to detect crashed workers that didn't clean up
- Marks linked agent as `failed` (mirroring the archive path)
- Sets `status_reason: "zombie_swept"` for visibility
- Guards against fresh sessions with NULL `last_activity_at` by checking `started_at` is stale (>30min old)

This handles production scenarios where AgentWorker crashes abnormally without calling terminate/2.

**AgentWorker Abnormal Exit:**
When AgentWorker terminates for abnormal reasons (not `:normal` or `:shutdown`), the worker's `terminate/2` callback calls `on_session_failed/2` to:
1. Mark the session status as `failed` in the database
2. Stream an error event to the session channel
3. Sync the linked team member (if any) to `failed` status
4. Set `status_reason` appropriately for visibility

The system catches agent crashes via two mechanisms:
1. **Synchronous**: AgentWorker terminate/2 on abnormal exit (non-zero exit code)
2. **Async**: Periodic zombie sweep marks sessions stuck in `working` >30 minutes with no heartbeat as `failed`

This dual approach ensures:
- Systemic failures are distinguishable from graceful stops (UI shows red status)
- Crashed workers are caught immediately, or eventually by the sweep
- Status is written to DB (survives process restart)
- No duplicate broadcast events from status finalization

**Status indicator styling:**
- `idle` → Neutral gray left border on session card
- `working` → Blue left border
- `failed` → Red left border
- `waiting` → Yellow left border (awaiting action/resume)

### Display Status to Atom Conversion

The display status string returned by `StatusHelpers.derive_display_status/2` must be converted to an Elixir atom for use in UI component styling and logic. Prior implementations used `String.to_existing_atom/1`, which crashes at runtime when the status string (e.g., `"failed_retry_exhausted"`) has never been registered as an atom in the running codebase — type specs alone do not register atoms.

**Fix (commit c3ff50bc):** The `SessionCard` component now uses an exhaustive private function `display_status_to_atom/1` that maps all known display status strings to atom literals:

```elixir
defp display_status_to_atom(status) do
  case status do
    "working" -> :working
    "waiting" -> :waiting
    "compacting" -> :compacting
    "idle" -> :idle
    "idle_stale" -> :idle_stale
    "idle_dead" -> :idle_dead
    "completed" -> :completed
    "failed" -> :failed
    "failed_billing" -> :failed_billing
    "failed_auth" -> :failed_auth
    "failed_rate_limit" -> :failed_rate_limit
    "failed_timeout" -> :failed_timeout
    "failed_retry_exhausted" -> :failed_retry_exhausted
    _ -> :idle
  end
end
```

**Key behaviors:**
- All known statuses (including failed tier variants like `failed_billing`, `failed_auth`, `failed_retry_exhausted`) are explicitly mapped
- Unknown statuses fall back to `:idle` for graceful degradation
- The function is private to `SessionCard` and intentionally exhaustive to catch missing mappings at compile time (via pattern matching warnings in CI)

This prevents `ArgumentError` crashes when UI renders sessions with newly-added error statuses that haven't been manually tested.

**Auto-completion behavior:**
- Status is **not** auto-set on CLI exit (Stop hook sets `idle`, not `completed`)
- Completed status must be set **explicitly** via i-end-session skill or `POST /sessions/:id/complete`
- This prevents incorrect status when sessions are retried or resumed

---

## Session Intent (Read-Only Mode)

The `read_only` field on sessions declares whether the session is in **review mode** (read-only, intent to observe) or **work mode** (default, intent to execute). This allows hooks and spawned agents to make smarter decisions about enforcement.

**Semantics:**
- `read_only: false` (default) — **Work mode.** Session is executing user requests, file edits, agent spawns. Pre-tool-use hooks enforce task gate (Stop hook checks that in-progress task is closed).
- `read_only: true` — **Review mode.** Session is read-only: browsing, analyzing, documenting. Pre-tool-use hooks may skip enforcement (e.g., task gate is not mandatory).

**Set at Creation:**
```bash
# Create a new session in review mode
eits sessions create --session-id <uuid> --read-only

# Create in work mode (default)
eits sessions create --session-id <uuid>
```

**Set on Existing Session:**
```bash
# Switch to review mode (read-only)
eits sessions set-intent review <uuid>

# Switch to work mode (default)
eits sessions set-intent work <uuid>

# Defaults to EITS_SESSION_UUID when uuid is omitted
eits sessions set-intent review
eits sessions set-intent work
```

**API:**
```bash
# Set read_only via PATCH
curl -X PATCH http://localhost:5001/api/v1/sessions/<uuid> \
  -d '{"read_only": true}'

# Check current intent in eits me output
eits me
# Shows Session Intent section:
#   intent: review  (read-only — task enforcement skipped)
#   intent: work    (default — pre-tool-use hooks enforce task)
```

**Response Format:**
The `read_only` field is exposed in session API responses:
```json
{
  "id": 3185,
  "uuid": "8803d56d-dbbd-4916-9ff0-155378a64a47",
  "status": "working",
  "read_only": true
}
```

**Hook Integration:**
Pre-tool-use hooks (e.g., `eits-task-gate.sh`) can check the session's read_only intent and skip enforcement for review-mode sessions. This prevents spurious "task not closed" failures when browsing code or documenting work.

---

## Sessions.HookRegistrar Sub-Module

Hook session registration was extracted from the main Sessions module into `EyeInTheSky.Sessions.HookRegistrar` (64 lines, commit 1779981c) to separate hook-driven registration logic from general session management. The Sessions module delegates the entry point via `defdelegate`:

### register_from_hook/2

```elixir
@spec register_from_hook(map(), integer() | nil) ::
        {:ok, %{session: Session.t(), agent: struct()}}
        | {:error, :agent | :session, Ecto.Changeset.t()}
def register_from_hook(params, project_id)
```

**Purpose:** Register a new session from a SessionStart hook payload (e.g., `eits-session-startup.sh`).

**Input Parameters:**
- `params` (map) — raw hook payload with keys: `session_id`, `agent_id`, `agent_description`, `description`, `project_name`, `worktree_path`, `model`, `name`, `provider`, `entrypoint`, `read_only`
- `project_id` (integer | nil) — pre-resolved project ID (may be nil if project wasn't found during startup)

**Workflow:**
1. **Find or create agent** — Calls `Agents.find_or_create_agent/1` with agent attributes (UUID, description, project context, source: "hook")
2. **Parse model info** — Extracts model provider and name via `ModelInfo.parse_model_string/1`
3. **Create session** — Calls either `Sessions.create_session_with_model/1` or `Sessions.create_session/1` depending on whether model_name was parsed
4. **Fire event** — On success, fires `Events.session_started/1` for downstream listeners
5. **Return result** — Returns `{:ok, %{session: session, agent: agent}}` on success, or `{:error, :agent | :session, changeset}` on failure

**Error handling:**
- Returns `{:error, :agent, changeset}` if agent creation fails
- Returns `{:error, :session, changeset}` if session creation fails
- Either error short-circuits the workflow — both agent and session must succeed

**Usage:** Called by the startup hook when initializing a new Claude Code session.

---

## Session Auto-Registration (Startup Hook)

The startup hook (`priv/scripts/eits-session-startup.sh`) now automatically registers new sessions when they are not pre-registered (e.g., not spawned by the orchestrator). This eliminates the need for manual `eits-init` invocation in normal operation.

**Auto-Registration Flow:**

1. **Check pre-registration**: Startup hook calls `eits sessions get $EITS_SESSION_UUID` to see if session was pre-created (spawned agent or spawn endpoint).
2. **Auto-register if missing**: When `sessions get` returns nothing, the hook calls:
   ```bash
   eits sessions create \
     --session-id "$SESSION_ID" \
     --project "$(basename "$LOOKUP_DIR")" \
     --project-path "$LOOKUP_DIR" \
     --model "${MODEL:-}" \
     --entrypoint "${ENTRYPOINT:-}"
   ```
3. **Extract agent UUID**: On success, extracts `EXISTING_AGENT_UUID` and `SESSION_INT_ID` from the create response and exports them.
4. **Fallback on failure**: If create fails (server down), hook logs a message and proceeds — `EITS_AGENT_UUID` remains unset, and `eits-init` skill is available as a fallback.

**Coverage:**
- All new interactive `cli` sessions (normal user-initiated Claude Code)
- All new headless `sdk-cli` sessions (spawned agents, resumed agents)
- Spawned agents pre-registered by the orchestrator skip this path (already have `EXISTING_AGENT_UUID` set)

**Fallback Skill (`eits-init`):**

The `eits-init` skill is now a fallback for auto-registration failures (server down at session start). The skill description and behavior have been updated:

**Before:** "MUST be called at the start of every session..."
**After:** "Fallback session registration for EITS. Only needed when auto-registration in the startup hook failed (EITS server was down at session start). Check $EITS_AGENT_UUID first — if set, exit immediately."

When auto-registration fails, the startup hook output includes:
```
[EITS] startup: auto-register failed — EITS server may be down
**IMPORTANT**: Auto-registration failed (EITS server may be down). Invoke `skill: "eits-init"` before responding to the user.
```

When auto-registration succeeds, the output includes:
```
[EITS] startup: auto-registered session_int=$SESSION_INT_ID agent_uuid=$EXISTING_AGENT_UUID
Session registered. EITS_AGENT_UUID is set — /eits-init is not needed.
```

---

## Session Usage Caching

Session token and cost totals are cached on the `sessions` table for O(1) lookup when displaying per-session usage metrics.

**Schema:**
- `total_tokens` — integer, default 0
- `total_cost_usd` — float, default 0.0

**Atomic Increment:**
Each time a message with usage metadata is inserted (`Messages.create_message` or `create_channel_message`), the helper `maybe_increment_session_cache/1` parses the message metadata and calls `Sessions.increment_usage_cache/3`:

```elixir
Sessions.increment_usage_cache(session_id, input_tokens + output_tokens, total_cost_usd)
```

This uses a raw SQL `UPDATE .. inc` for atomicity — no read-modify-write race.

**Fallback Query:**
Aggregation functions (`Messages.Aggregations.total_tokens_for_session/1` and `total_cost_for_session/1`) read the cached column first. When the value is `nil` (pre-cache sessions created before migration `20260501110334`), they fall back to a full aggregate scan over the messages table.

**Behavior:**
```elixir
def total_tokens_for_session(session_id) do
  case Repo.one(from s in Session, where: s.id == ^session_id, select: s.total_tokens) do
    nil -> aggregate_tokens_for_session(session_id)
    cached -> cached
  end
end
```

This allows zero-cost lookups for active sessions while maintaining backward compatibility with older data.

---

## Sessions REST API

The Sessions API at `PATCH /api/v1/sessions/:uuid` and related endpoints uses `Sessions.resolve(uuid)` to support both numeric session IDs and UUIDs:

```elixir
# Both work:
PATCH /api/v1/sessions/3185                                        # numeric session ID
PATCH /api/v1/sessions/8803d56d-dbbd-4916-9ff0-155378a64a47       # UUID
```

**Endpoints using `resolve_session/1`:**
- `PATCH /api/v1/sessions/:uuid` — Update session status, read_only intent, and other fields (lifecycle hooks)
  - Parameters: `status`, `status_reason`, `intent`, `read_only`, `entrypoint`, `name`, `description`
- `POST /api/v1/sessions/:uuid/tool_event` — Record tool event
- `POST /api/v1/sessions/:uuid/end` — End session with final status
- `POST /api/v1/sessions/:uuid/complete` — Mark session completed and sync team member (NEW)
- `POST /api/v1/sessions/:uuid/waiting` — Mark session waiting with optional status_reason and sync team member (NEW)
- `POST /api/v1/sessions/:uuid/reopen` — Clear ended_at and set status to idle (NEW)
- `GET /api/v1/sessions/:uuid/context` — Load session context
- `POST /api/v1/sessions/:uuid/context` — Upsert context

This flexibility allows CLI scripts and hooks to use either the shorter numeric ID or the full UUID interchangeably.

### Session UUID Validation (get_session_by_uuid/1)

The `Sessions.get_session_by_uuid/1` function validates UUID format before querying the database to prevent `Ecto.Query.CastError` exceptions when non-UUID strings are passed (commit 0c5f130b):

```elixir
@spec get_session_by_uuid(String.t()) :: {:ok, Session.t()} | {:error, :not_found}
def get_session_by_uuid(uuid) when is_binary(uuid) do
  case Ecto.UUID.cast(uuid) do
    {:ok, _} -> get_by_uuid(uuid)
    :error -> {:error, :not_found}
  end
end
```

**Problem:** `Sessions.resolve/1` passes arbitrary strings (e.g., filenames, numeric IDs) to `get_session_by_uuid`. When a non-UUID string was passed directly to `Repo.get_by`, PostgreSQL would raise `Ecto.Query.CastError`, crashing the request.

**Solution:** Validate UUID format using `Ecto.UUID.cast/1` before querying:
- `{:ok, _}` — UUID is valid, proceed to `get_by_uuid/1`
- `:error` — Not a valid UUID, return `{:error, :not_found}` gracefully

**Impact:**
- Non-UUID strings (e.g., filenames from worktree paths) return `:not_found` instead of raising
- Sessions REST API routes that accept numeric IDs or UUIDs continue to work — `resolve/1` tries numeric lookup first, then falls back to UUID validation
- Graceful degradation: malformed UUID strings are treated as "no session found" rather than server errors

**Example flow:**
```bash
# Valid UUID
curl /api/v1/sessions/8803d56d-dbbd-4916-9ff0-155378a64a47
# → get_session_by_uuid validates, finds session

# Invalid UUID (e.g., a filename)
curl /api/v1/sessions/.claude/worktrees/fix-bug/notes.md
# → Ecto.UUID.cast fails, returns {:error, :not_found}
# → 404 response (graceful)

# Numeric ID still works (resolve tries this first)
curl /api/v1/sessions/3185
# → resolve tries numeric lookup, succeeds
```

### Agent Type Resolution for IAM Policy Evaluation

When Claude Code hooks evaluate session-scoped policies (e.g., document-attached policies that scope enforcement by agent type), the hook payload from the Claude CLI may not include an explicit `agent_type` field. To ensure policies fire correctly, the IAM controller enriches hook payloads with the agent type resolved from the session record.

**Function:** `Sessions.agent_type_for_session/1`

```elixir
def agent_type_for_session(uuid) when is_binary(uuid) do
  result =
    from(s in Session,
      join: a in assoc(s, :agent),
      join: ad in assoc(a, :agent_definition),
      where: s.uuid == ^uuid,
      select: ad.slug,
      limit: 1
    )
    |> Repo.one()

  case result do
    nil -> :error
    slug -> {:ok, slug}
  end
end
```

**Purpose:** Resolves the agent definition slug (e.g., `"setup-guardian"`) for a session identified by its UUID via a three-table join (Session → Agent → AgentDefinition). Returns `{:ok, slug}` when found, `:error` when the session, agent, or agent definition is missing.

**Usage in IAM Controller:** `POST /api/v1/iam/decide` enriches the hook payload before policy evaluation:

```elixir
def decide(conn, params) when is_map(params) do
  start_us = System.monotonic_time(:microsecond)

  params = enrich_agent_type(params)  # Enrich with agent type from session
  ctx = Normalizer.from_hook_payload(params)
  decision = Evaluator.decide(ctx)

  # ... broadcast and return
end

defp enrich_agent_type(params) do
  with nil <- Map.get(params, "agent_type"),
       uuid when is_binary(uuid) <- Map.get(params, "session_id"),
       {:ok, slug} <- Sessions.agent_type_for_session(uuid) do
    Map.put(params, "agent_type", slug)
  else
    _ -> params
  end
end
```

**Behavior:**
- Uses `put_new` semantics — if `agent_type` is already in the payload, it is not overwritten
- Falls back gracefully: if the session, agent, or agent definition is missing, the payload remains unchanged (policy evaluation may skip document-attached policies that require agent type)
- O(1) lookup: single three-table join with limit 1; no N+1 risk

**Example flow:**
1. Claude Code hook posts `{session_id: "uuid-...", tool: "Edit", ...}` (no agent_type)
2. IAM controller calls `agent_type_for_session("uuid-...")`
3. Resolves to `{:ok, "setup-guardian"}` by joining Session → Agent → AgentDefinition
4. Enriches params: `Map.put(params, "agent_type", "setup-guardian")`
5. Policy evaluator now has agent_type for document-scoped policies
6. Policies that target agent type "setup-guardian" fire correctly

### Session Resume Response

When a session is resumed via `POST /api/v1/sessions/:uuid/resume` or fetched via `GET /api/v1/sessions/:uuid`, the response includes the agent UUID, project ID, and worktree information needed to set up the Claude Code environment:

```json
{
  "id": 3185,
  "uuid": "8803d56d-dbbd-4916-9ff0-155378a64a47",
  "agent_id": 42,
  "agent_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "project_id": 1,
  "status": "idle",
  "worktree_path": "/path/to/project/.claude/worktrees/fix-auth-bug",
  "branch_name": "worktree-fix-auth-bug"
}
```

**Key fields:**
- `agent_uuid` — Claude agent UUID (for `EITS_AGENT_UUID` env var) — now correctly populated on resume (previously hardcoded to null)
- `project_id` — Project integer ID (for project-scoped operations) — now correctly populated on resume (previously hardcoded to null)
- `worktree_path` — Absolute path to git worktree (from `sessions.git_worktree_path`); `null` if session was not started in a worktree (commit 360e0fc1)
- `branch_name` — Current git branch name resolved at request time via `git symbolic-ref --short HEAD` inside the worktree; `null` if `worktree_path` is null or the path no longer exists (commit 360e0fc1)

The addition of `worktree_path` and `branch_name` eliminates orchestrator guessing on branch names before merge — the API now surfaces the exact branch the session is working on.

This fix ensures the startup hook can properly populate `EITS_AGENT_UUID` and `EITS_PROJECT_ID` in the Claude Code environment when resuming a session.

### Session Resume Context Injection — Channel Mentions

When a session resumes via `eits sessions resume <uuid>` or the session lifecycle hooks, the `eits-session-resume.sh` script injects recent channel activity for awareness. This allows resumed agents to pick up context on what happened while they were paused.

**What gets injected:**
- Messages from channels where the session is a member **AND** was directly @mentioned in the last hour
- Up to 3 most recent messages per qualifying channel
- Message sender, timestamp, and truncated body (200 chars max)
- Pure ambient-observer channels (no direct mention) are skipped — avoids noise for agents that only passively listen

**Example injected context:**
```markdown
## Recent Channel Activity (last 1h — you were @mentioned)

### #tech-review (channel:42)
- **alice** [14:23]: Design feedback on PR #156: we need to…
- **bob** [14:15]: @3185 can you review the auth changes?
- **charlie** [14:05]: Updated schema migration, ready for QA
```

**Implementation:** Shell function `_inject_channel_context()` in `priv/scripts/eits-session-resume.sh`:
1. Queries the DB using `psql` directly against `EITS_PG_*` env vars
2. Filters channels by session membership + @mention by session ID or UUID in the last hour
3. Formats top 3 messages per channel chronologically
4. Falls back gracefully if `psql` is unavailable or no qualifying channels exist
5. Appends context to the system-reminder section output

**Query behavior:**
- Uses a CTE to find mentioned channels first (efficient for sparse @mentions)
- Rows from other sessions only (excludes self-mentions)
- Case-insensitive ILIKE match on session ID (numeric) or UUID (string format)
- Runs only when session has a numeric ID (`SESSION_INT_ID` env var is set)

This allows resumed agents to recover context automatically — no explicit "catch me up" request needed. Particularly useful for long-running orchestrators that pause and resume across task boundaries, or for agents that were idle while important discussions happened in team channels.

**Environment Variable: EITS_SESSION_ID**
Spawned Claude processes set `EITS_SESSION_ID` to the **integer EITS session record ID**, not the UUID. This is critical for child agent spawning:
- `EITS_SESSION_ID` = integer (e.g., `3185`) — set by eits-session-startup.sh during agent startup; used for `--parent-session-id` 
- `EITS_SESSION_UUID` = UUID (e.g., `8803d56d-dbbd-4916-9ff0-155378a64a47`) — set by provider; used for `--resume`
- Provider conversation ID (Claude session UUID) is separate; stored in agents table for `--resume` handling

**Fixed in commit 2d49d0e2:** The startup hook was fetching session info (which includes `.id`) but only extracting `agent_id` and `agent_int_id` — the session's own integer ID was silently dropped. Now extracts `SESSION_INT_ID=.id` from `eits sessions get` and writes it to `CLAUDE_ENV_FILE` as `EITS_SESSION_ID`, matching what the resume hook already does.

Agents that spawn children read `EITS_SESSION_ID` and pass it as `--parent-session-id` to `eits agents spawn`. The `--parent-session-id` parameter now accepts both integer strings and UUID formats (commit 2d49d0e2):
- Integer: `eits agents spawn --parent-session-id 3185 ...`
- UUID: `eits agents spawn --parent-session-id 8803d56d-dbbd-4916-9ff0-155378a64a47 ...`

The change was necessary because `--argjson` in jq rejects non-JSON literals (UUIDs); now uses `--arg` so both formats pass through as strings — the server's `coerce_session_ref` already accepts both formats.

**Integer Session ID Handling:**
JSON decoding converts numeric `session_id` values to integers, but task linking functions only had clauses for nil and binary strings. Fixed by adding integer guards to `do_link_session/2` in `Tasks.Associations` and `maybe_link_session/2` in `TaskController`:

```elixir
# Tasks.Associations
defp do_link_session(task_id, session_id) when is_integer(session_id) do
  TaskSessions.link_session_to_task(task_id, session_id)
  :ok
end

# TaskController
defp maybe_link_session(task_id, session_id) when is_integer(session_id) do
  case parse_task_id(task_id) do
    nil -> :ok
    task_int_id -> Tasks.link_session_to_task(task_int_id, session_id)
  end
  :ok
end
```

This prevents `FunctionClauseError` when JSON payloads contain numeric session IDs.

**Parent Session ID Flexible Format:**
The `eits agents spawn --parent-session-id` parameter now accepts both formats for convenience:
- Integer: `eits agents spawn --parent-session-id 3185 ...`
- UUID: `eits agents spawn --parent-session-id 8803d56d-dbbd-4916-9ff0-155378a64a47 ...`

This unifies the parent/child spawn pattern with other CLI commands like `eits dm --to` which already accept both integer and UUID formats. The server-side `SpawnValidator` uses `Ecto.UUID.cast` to validate UUID format, rejecting malformed strings before they reach the database (which would raise `Ecto.Query.CastError`).

---

## Explicit Session Completion Endpoints

Two new endpoints provide explicit control over session status transitions with team member synchronization:

### POST /api/v1/sessions/:id/complete

Sets session status to `completed` and marks the team member as done (for the calling session only):

```bash
curl -X POST http://localhost:5001/api/v1/sessions/8803d56d-dbbd-4916-9ff0-155378a64a47/complete
```

**Response:**
```json
{
  "status": "completed",
  "member_synced": true
}
```

- Accepts integer ID or UUID
- Returns `member_synced: true` if the session was part of a team
- CLI: `eits sessions complete` defaults to `EITS_SESSION_UUID`

### POST /api/v1/sessions/:id/waiting

Sets session status to `waiting` and marks the team member as blocked:

```bash
curl -X POST http://localhost:5001/api/v1/sessions/8803d56d-dbbd-4916-9ff0-155378a64a47/waiting \
  -d '{"status_reason": "awaiting user input"}'
```

**Response:**
```json
{
  "status": "waiting",
  "status_reason": "awaiting user input",
  "member_synced": true
}
```

- Accepts integer ID or UUID
- Optional `status_reason` param
- Auto-clears `status_reason` if transitioning away from `waiting` without an explicit reason
- CLI: `eits sessions waiting` defaults to `EITS_SESSION_UUID`

### POST /api/v1/sessions/:id/reopen

Clears `ended_at` and sets status to `idle`. Use when a resume hook fails to reset status, or when an orchestrator needs to post work against an already-ended session:

```bash
curl -X POST http://localhost:5001/api/v1/sessions/8803d56d-dbbd-4916-9ff0-155378a64a47/reopen
```

**Response:**
```json
{
  "status": "idle",
  "member_synced": false
}
```

- Accepts integer ID or UUID
- Fires `session_updated` broadcast after the DB write
- CLI: `eits sessions reopen [uuid|self]`

---

## Task Execution & Ownership

### Claim & Session Transfer

When a session claims a task via `POST /api/v1/tasks/:id/claim`, the system **atomically transfers session ownership** to the claimer:

**Old approach (deprecated):**
- `eits tasks claim` used `PATCH /tasks/:id` with `state: "start"` and called link_session separately
- Risk: if the session wasn't in the DB yet, it might not be linked, and the stop hook would fire on the wrong session

**New approach (atomic):**
- `POST /api/v1/tasks/:id/claim` transitions to In Progress and atomically:
  1. Removes **all** existing `task_sessions` entries for the task
  2. Inserts a new entry linking the claimer's session
  3. Transitions task state to "in-progress" (state_id = 2)

This ensures the stop hook fires on the executing session, not the creator's session.

**Implementation** in `TaskSessions.transfer_session_ownership/2`:
```elixir
def transfer_session_ownership(task_id, new_session_id)
    when is_integer(task_id) and is_integer(new_session_id) do
  Repo.transaction(fn ->
    from(ts in "task_sessions", where: ts.task_id == ^task_id)
    |> Repo.delete_all()

    Repo.insert_all(
      "task_sessions",
      [%{task_id: task_id, session_id: new_session_id}],
      on_conflict: :nothing
    )
  end)

  {:ok, new_session_id}
end
```

**Atomicity guards:**
- Task row is locked with `FOR UPDATE` until the transaction completes
- Nil-guard in `transfer_session_ownership/2` ensures the task exists before proceeding
- Precondition checks: 
  - `:task_not_found` — task does not exist
  - `:already_claimed` — task state is already in-progress (cannot claim twice)
- Single `Repo.transaction` ensures no partial success — if any step fails, the entire claim is rolled back

### Created By Tracking

Tasks now track who created them via the `created_by_session_id` column. This is separate from session ownership (task_sessions).

**Key distinctions:**
- **`created_by_session_id`** — immutable, set at task creation, tracks the original creator
- **`task_sessions`** — mutable via claim, tracks the current executor

**Use in filtering:**
```bash
eits tasks list --created-by        # Tasks created by the current session
eits tasks list --mine --assigned   # Tasks currently assigned to the current session (via task_sessions)
```

### Task Completion & Member Status

When `eits tasks complete` is called, it marks the team member as done **for the calling session only** (commit b3a98e8f):

**Problem:** Previously `mark_member_done_by_session` was called for all sessions linked to the completed task, which could mark unrelated team members (e.g., the orchestrator) as done.

**Solution:**
- CLI passes `EITS_SESSION_UUID` (or `EITS_SESSION_ID`) as `session_id` parameter
- Controller only marks that single session's member done via `maybe_mark_member_done`
- Other sessions linked to the same task remain unaffected

**Implementation** in `TaskController.complete`:
```elixir
defp maybe_mark_member_done(nil), do: :ok
defp maybe_mark_member_done(""), do: :ok

defp maybe_mark_member_done(session_id) do
  case Helpers.resolve_session_int_id(session_id) do
    {:ok, int_id} -> Teams.mark_member_done_by_session(int_id)
    _ -> :ok
  end
end
```

The `mark_member_done_by_session/2` function now returns a count of updated members for accuracy (commit 5d4205a2), allowing `member_synced` to report true/false based on whether any members were actually synced.

**Error Handling:**
The `sync_member_status/2` helper function has a bare rescue clause that catches exceptions from `Teams.mark_member_done_by_session/2` operations. A warning log is now generated on rescue, enabling debugging of team member status sync failures:

```elixir
defp sync_member_status(session_id, member_status) do
  EyeInTheSky.Teams.mark_member_done_by_session(session_id, member_status) > 0
rescue
  e ->
    Logger.warning("sync_member_status failed for session #{session_id}: #{inspect(e)}")
    false
end
```

This allows operators to detect and diagnose team member sync failures in logs.

### Annotation Retry & Persistence

Task annotations (`eits tasks annotate`) now retry on rate-limit (429) errors and persist to disk on failure:

**Retry strategy:**
- Exponential backoff: 2s, 4s, 8s (max 3 retries)
- After 3 failed attempts, annotation is queued to `~/.eits/pending-annotations.log`

**Persistence & drain:**
- Failed annotations are serialized as JSON to `~/.eits/pending-annotations.log`
- On next session startup, `eits-session-startup.sh` drains the log sequentially
- Each drained annotation retries with the same backoff strategy
- Successfully drained entries are removed; failed ones are re-queued

**Log format:**
```json
{"task_id":"123","body":"Completed xyz","title":""}
```

This prevents losing annotations when the API is temporarily rate-limited or unavailable.

---

## Stop Hook Task-Gate Enforcement

The Stop hook (`eits-task-gate.sh`) enforces that agents must close their in-progress task before stopping. However, this enforcement is skipped for orchestrator turns that only spawn sub-agents and run coordination calls without mutating files (commit c2fc82da).

**Spawn-Only Turn Detection:**
The hook parses the transcript JSONL to detect whether file edits occurred since the last user message:
1. Find the index of the most recent `user` type entry
2. Scan all `assistant` entries after it for file-editing tool_uses (Edit, Write, MultiEdit, NotebookEdit)
3. If no file edits found, exit 0 (skip enforcement)

**Rationale:**
An orchestrator that only spawns sub-agents via the `Agent` tool and runs Bash/eits coordination calls shouldn't be forced to close its task every turn. It's still coordinating. Only block Stop when the turn actually mutated files (Edit, Write, etc.). If no edits happened, the turn was coordination-only and the task should remain open for the next turn.

**Edge cases:**
- Multi-turn orchestration: task remains open across turns that don't edit files
- Mixed turns: first turn only spawns (skips enforcement) → second turn edits files (enforces)
- Agent spawns on last turn: skips enforcement since no edit occurred

---

## Session Context & Metadata

Session context is stored in the `session_context` table, linked to sessions and agents:

**Schema** (`EyeInTheSky.Contexts.SessionContext`):
```elixir
schema "session_context" do
  field :context, :string          # Serialized session context (CLAUDE.md, imports, etc.)
  field :metadata, :map            # Key-value metadata with source tracking
  field :agent_id, :integer        # Agent who owns this context
  field :session_id, :integer      # Session ID (not a foreign key, just a field)
  field :created_at, :utc_datetime_usec
  field :updated_at, :utc_datetime_usec
end
```

**Metadata Field:**
The `metadata` field (`:map`) stores arbitrary metadata with a `source` key for tracking context origins:
```json
{
  "source": "resolved via session.project_id"
}
```

Indexed on `metadata->>'source'` for efficient filtering of context by origin.

**Changeset fields:**
Only these are writable: `:agent_id, :session_id, :context, :metadata`

---

## Project Path Resolution

When spawning agents, the system must resolve the working directory (`resolve_project_path`). The resolution order is:

1. **Agent project association** (`agent.project.path`) — direct path from agent's project
2. **Session project path** (`session.project.path`) — project directly linked to session
3. **Session project ID fallback** (`session.project_id`) — look up project by ID if path is nil
4. **Agent project ID fallback** (`agent.project_id`) — look up project by ID if agent.project is nil
5. **Missing** — return `{:error, :missing_project_path}`

Implementation in `SessionBridge.resolve_project_path/1`:
```elixir
case {session.project && session.project.path, agent.project && agent.project.path} do
  {path, _} when not is_nil(path) -> {:ok, path}
  {_, path} when not is_nil(path) -> {:ok, path}
  {_, _} ->
    case session.project_id || agent.project_id do
      project_id when is_integer(project_id) ->
        lookup_project_path(project_id, source, session.id)
      _ ->
        {:error, :missing_project_path}
    end
end
```

The `--project-id` flag in `eits sessions update` and the session startup script allow new sessions to set their project_id early, enabling path resolution before other data arrives.

---

## Session Naming

When spawning agents via `eits agents spawn`, the system resolves a display name for the session using a priority fallback chain:

**Name Resolution Priority:**
1. **Explicit `--name` parameter** (trimmed, non-empty) — direct user-provided name
2. **Team member assignment** (`member_name @ team_name`) — when both `--member-name` and team are provided
3. **Agent slug** (e.g., `setup-guardian`) — from the `--agent` parameter
4. **Timestamp fallback** (e.g., `May 7 14:23:45`) — when no agent slug is provided

**Previous behavior (deprecated):** Session names fell back to the first 250 characters of `--instructions` text, which was often unhelpful (verbose or truncated) and made sessions hard to identify in UIs.

**New behavior:** The system now prefers the concise agent slug, and only generates a datetime stamp if no agent slug is available. This keeps session names human-readable and useful for filtering/searching.

**Examples:**
```bash
# Uses agent slug "setup-guardian"
eits agents spawn --agent setup-guardian --instructions "..."
→ Session name: "setup-guardian"

# Uses explicit name
eits agents spawn --agent setup-guardian --name "My Custom Name" --instructions "..."
→ Session name: "My Custom Name"

# Uses timestamp when agent slug missing
eits agents spawn --instructions "..." --parent-session-id 123
→ Session name: "May 7 14:23:45"

# Uses team member context
eits agents spawn --agent setup-guardian --member-name alice --team-name builders --instructions "..."
→ Session name: "alice @ builders"
```

---

## PTY Session Creation

Two behaviors govern how sessions are created and launched from the web UI.

### dm_use_pty Branching

Session creation callers — `AgentLive.IndexActions`, `ProjectLive.Sessions.Actions`, and `WorkspaceLive.Sessions.Actions` — branch on the `dm_use_pty` setting when creating a new session:

```elixir
create_fn =
  if EyeInTheSky.Settings.get_boolean("dm_use_pty"),
    do: &AgentManager.create_pty_session/1,
    else: &AgentManager.create_agent/1

case create_fn.(opts) do
  ...
end
```

| `dm_use_pty` | Function called | Mode |
|---|---|---|
| `true` | `AgentManager.create_pty_session/1` | PTY (interactive terminal, xterm.js) |
| `false` (default) | `AgentManager.create_agent/1` | SDK/messages mode |

**Why:** The DM page only subscribes to PTY output when `dm_use_pty=true`. Before this fix, all three callers unconditionally called `create_pty_session` regardless of the setting, leaving the DM page blank for any session created with `dm_use_pty=false`.

### Worktree Path in Launch Command

`AgentManager.create_pty_session/1` now uses `agent.git_worktree_path` as the working directory in the Claude CLI launch command, falling back to `opts[:project_path]`:

```elixir
# Use the resolved worktree path from the agent record (set by RecordBuilder
# after creating the git worktree), falling back to the raw project path.
working_path = agent.git_worktree_path || opts[:project_path]
cd_part = if working_path && working_path != "", do: "cd #{working_path} && ", else: ""
launch_cmd = "#{cd_part}claude --session-id #{session.uuid}\n"
```

**Why:** Previously `create_pty_session` used `opts[:project_path]` (the base project directory) as the working directory, ignoring the git worktree path resolved by `RecordBuilder`. This caused the PTY session to launch Claude in the wrong directory when a session had a worktree. The DM page's `build_launch_command` already used the correct worktree path — this fix brings `create_pty_session` into alignment with that logic.

---

## Worktree Management

Agent workers use git worktrees to isolate CLI processes and prevent conflicts on concurrent spawns.

**Location:** `lib/eye_in_the_sky_web/git/worktrees.ex` (Git.Worktrees module)

**Key behaviors:**
- Worktrees reuse existing paths on repeated `prepare_session_worktree/2` calls
- Dirty state check filters untracked files (`git status --porcelain` with `??` filter)
  - Untracked files are irrelevant to worktree creation since worktrees branch from HEAD
  - Allows multiple worktrees on repos without `.gitignore` rules for `.claude/worktrees/`
- Each agent gets a dedicated worktree at `.claude/worktrees/<session-uuid>`
- **Stale worktree detection:** Before calling `git worktree add`, the system pre-checks for stale branch entries via `check_stale_worktree/2`. If a branch is already registered in the worktree list from a prior pruned session, the spawn fails with a clear error message suggesting `git worktree prune` to clean up. This prevents confusing git errors and helps operators recover quickly.

**Stale worktree error response:**
```json
{
  "error_code": "worktree_conflict",
  "message": "worktree \"<name>\" has a stale git entry (branch worktree-<name> still registered). Run `git worktree prune` in <project_path> to clean up, then retry."
}
```

**Worktree fallback:**
- If worktree creation fails, agent falls back to main project directory
- Fallback is silent in non-critical paths; logged in debug contexts

---

## LiveView Safety Fixes

### set_notify_on_stop Event Handler Safety

All routed LiveViews must implement a `set_notify_on_stop` event handler to prevent GenServer crashes. The PushNotifications JS hook fires this event on every page load, and any LiveView without a matching `handle_event` clause will crash (commit a406e06d).

**Implementation via NotificationHelpers:**
```elixir
defmodule EyeInTheSkyWeb.NotificationHelpers do
  def notify_on_stop_handler(socket) do
    assign(socket, :notify_on_stop, true)
  end
end

# In any routed LiveView:
def handle_event("set_notify_on_stop", _params, socket) do
  {:noreply, NotificationHelpers.notify_on_stop_handler(socket)}
end
```

**Affected LiveViews (15 fixed):**
- `BookmarkLive.Index`
- `IAMLive.Policies`, `IAMLive.PolicyEdit`, `IAMLive.PolicyNew`
- `OverviewLive.Keybindings`, `OverviewLive.Usage`
- `ProjectLive.PromptNew`, `ProjectLive.PromptShow`, `ProjectLive.Prompts`, `ProjectLive.Show`, `ProjectLive.TeamShow`, `ProjectLive.Teams`
- `WorkspaceLive.NotesLive`, `WorkspaceLive.SessionsLive`, `WorkspaceLive.TasksLive`

Without this handler, PushNotifications hook initialization would silently crash the GenServer, leaving the user with a stale page and no error message visible.

### PubSub Unsubscribe Safety

LiveViews must use `Events.unsubscribe_session/1` instead of raw `Phoenix.PubSub.unsubscribe` calls. The Events module wraps unsubscribe with proper topic formatting and deduplication:

```elixir
# WRONG — raw PubSub call
Phoenix.PubSub.unsubscribe(EyeInTheSky.PubSub, "session:#{id}")

# CORRECT — use Events module
EyeInTheSky.Events.unsubscribe_session(id)
```

This ensures consistent topic naming and prevents unsubscribe errors when handlers change session topic subscriptions. Applied to `FloatingChatLive` (`fab_active_session_id`, `config_guide_active_session_id` handlers).

### Nil Project Crash Guard

`ProjectLive.Files.handle_params/3` must guard against nil project and redirect to home:

```elixir
def handle_params(_params, _uri, %{assigns: %{project: nil}} = socket) do
  {:noreply, push_navigate(socket, to: ~p"/")}
end

def handle_params(params, _uri, socket) do
  # ... normal flow
end
```

Without this guard, accessing project files after the project was deleted or project context was lost would crash with undefined behavior. The guard routes to home safely.

### FloatingChatLive Bookmark Query Optimization

`FloatingChatLive.fetch_bookmark_statuses/1` was refactored to use targeted Ecto queries instead of loading all sessions and filtering in memory (commit be14181d). The function now:

1. Parses the incoming `ids` list into integer IDs and UUIDs
2. Issues a targeted `from s in Session, where: s.id in ^ints or s.uuid in ^uuids` query
3. Handles empty lists and mixed integer/UUID formats

**Previous approach (N+1 pattern):**
- Loaded all sessions with `Sessions.list_sessions_with_agent(include_archived: false)`
- Filtered by MapSet membership in Elixir (memory overhead)

**New approach:**
```elixir
int_ids = ids |> Enum.flat_map(fn s -> case Integer.parse(s) do {n, ""} -> [n]; _ -> [] end end)
uuid_ids = ids |> Enum.filter(fn s -> case Ecto.UUID.cast(s) do {:ok, _} -> true; _ -> false end end)

sessions =
  case {int_ids, uuid_ids} do
    {[], []} -> []
    {[], uuids} -> Repo.all(from s in Session, where: s.uuid in ^uuids)
    {ints, []} -> Repo.all(from s in Session, where: s.id in ^ints)
    {ints, uuids} -> Repo.all(from s in Session, where: s.id in ^ints or s.uuid in ^uuids)
  end
```

This reduces DB load when rendering the floating chat sidebar, especially in workspaces with hundreds of bookmarked sessions.

### Project Live Show Mount Query Parallelization

`ProjectLive.Show.mount/3` parallelizes 6 independent DB queries using `Task.async/await` (commit 69392629). Previously, queries ran sequentially in the connected render path, blocking completion of mount until all 6 finished:

**Parallelized Queries:**
1. `Tasks.list_tasks_for_project(project_id)`
2. `Sessions.list_project_sessions_with_agent(project_id, active_only: true, limit: 5)`
3. `Notes.list_notes_for_project(project_id, limit: 5)`
4. `Agents.count_agents_for_project(project_id)`
5. `Sessions.count_and_ids_for_project(project_id)`
6. `scan_claude_files(project.path)` (filesystem scan)

**Implementation:**
```elixir
if connected?(socket) do
  tasks_task = Task.async(fn -> Tasks.list_tasks_for_project(project_id) end)
  active_sessions_task = Task.async(fn -> ... end)
  # ... spawn remaining 4 tasks
  
  tasks = Task.await(tasks_task)
  active_sessions = Task.await(active_sessions_task)
  # ... await remaining results
end
```

This reduces perceived mount latency — the page renders as soon as the slowest query completes (usually filesystem scan), not the sum of all 6. Tasks run concurrently on the pool, so wall-clock time approaches the duration of the slowest single query rather than serialized cumulative time.

---

## Session Filtering & Sorting

Session listing and filtering is handled by `EyeInTheSkyWeb.Helpers.SessionFilters` and is shared between the project sessions page and AgentLive's agent list.

### Filter Options

The `filter_agents_by_status/2` function supports the following filters:

| Filter | Meaning | Use Case |
|--------|---------|----------|
| `"working"` | Active sessions (status: working/idle/waiting/compacting), non-archived | Project sessions page default |
| `"active"` | Alias for "working"; backward compatibility | AgentLive agent list (deprecated filter name) |
| `"completed"` | Completed sessions, non-archived | AgentLive agent list (backward compatibility) |
| `"archived"` | Archived sessions | Project sessions page "Archived" tab |
| Any other value | Returns all sessions | Fallback; passes through |

**Backward Compatibility:**
- `"active"` is aliased to `"working"` via guard clause to maintain AgentLive compatibility
- `"completed"` branch is restored and functional for AgentLive sessions (even though project sessions page uses only "working"/"archived")
- The function is shared across both pages, so both filter names must be supported

### Parent Session Filter

`GET /api/v1/sessions` accepts a `parent_session_id` parameter (integer or UUID) to return only child sessions spawned by a specific parent. This is independent of all other filters (`--mine`, `--agent`, `--status`, `--project`):

```bash
# CLI
eits sessions list --parent <id|uuid>

# API
GET /api/v1/sessions?parent_session_id=3185
GET /api/v1/sessions?parent_session_id=8803d56d-dbbd-4916-9ff0-155378a64a47
```

Useful for lightweight parallel workflows where an orchestrator needs to inspect only the sessions it spawned without requiring a team.

### Sort Options

The `sort_agents/2` function supports sorting by:

| Sort Key | Meaning |
|----------|---------|
| `"recent"` (default) | Most recent message first (last_message_at descending) |
| `"name"` | Session name (case-insensitive alphabetical) |
| `"agent"` | Agent name (agent.description or agent.project_name; case-insensitive) |
| `"model"` | Model name (model_name or model field; case-insensitive) |
| `"status"` | Session status (working → idle → completed → archived) |
| `"created"` | Session creation date (created_at) |
| Any other value | Defaults to "recent" |

---

## Workspace Sessions Pagination

The workspace sessions page (`WorkspaceLive.Sessions`) paginates results using InfiniteScroll to avoid loading all sessions unbounded on large workspaces.

**Configuration:**
- Page size: 50 sessions per page
- Load trigger: InfiniteScroll sentinel element (`id="workspace-sessions-sentinel"`)
- Handler: `load_more` event fetches the next page via offset

**Implementation:**
Mount fetches the first page plus one extra sentinel to detect if there are more pages:
```elixir
sessions = Sessions.list_sessions_for_scope(socket.assigns.scope, limit: @page_size + 1)
{sessions, has_more} = split_page(sessions, @page_size)
```

When the InfiniteScroll sentinel reaches the viewport, the `load_more` handler fetches the next page:
```elixir
sessions = Sessions.list_sessions_for_scope(socket.assigns.scope, limit: @page_size + 1, offset: current_count)
```

**DB Support:**
- `list_sessions_for_scope/2` (workspace clause) now accepts `offset` parameter
- `list_project_sessions_with_agent/2` also supports `offset` for future pagination on project sessions

**Rationale (commit e981117b):**
Previously, mount was loading all sessions unbounded — project 1 had 1738 rows with full agent+agent_definition preloads and a 1738-ID IN clause for task titles. This caused slow initial render. Pagination with offset prevents DB and memory overhead on large workspaces.

---

## Routing Architecture

The application consolidates route handling into project-scoped LiveView modules. Previously, some resources had both global and project-scoped routes; global routes have been removed in favor of consistent project-scoped namespacing.

### Routing Consolidation

**Removed Global Routes** (commit d4fff39d):
| Removed Route | Was Handled By | Migration |
|---|---|---|
| `/notes` | `OverviewLive.Notes` | → `/projects/:id/notes` → `ProjectLive.Notes` |
| `/tasks` | `OverviewLive.Tasks` | → `/projects/:id/tasks` → `ProjectLive.Tasks` |
| `/jobs` | `OverviewLive.Jobs` | → `/projects/:id/jobs` → `ProjectLive.Jobs` |
| `/teams` | `TeamLive.Index` | → `/projects/:id/teams` → `ProjectLive.Teams` |
| `/prompts` | `PromptLive.Index` | → `/projects/:id/prompts` → `ProjectLive.Prompts` |
| `/prompts/new` | `PromptLive.New` | → `/projects/:id/prompts/new` → `ProjectLive.PromptNew` |
| `/prompts/:id` | `PromptLive.Show` | → `/projects/:id/prompts/:prompt_id` → `ProjectLive.PromptShow` |

**New Project-Scoped Routes:**
```
/projects/:id/teams          → ProjectLive.Teams (:index)
/projects/:id/prompts/new    → ProjectLive.PromptNew (:new)
/projects/:id/prompts/:prompt_id → ProjectLive.PromptShow (:show)
```

### Context-Aware Filtering

Project-scoped routes use `mount_project/2` helper and `handle_params/3` guards to ensure:
- LiveViews are project-context aware
- Nil project redirects to home (ProjectLive.Files safety guard pattern)
- Authorization checks (e.g., prompt.project_id matches current project)
- Dead-render DB calls are guarded with `connected?(socket)`

---

## Rate Limiting

Rate limiting is handled by the `EyeInTheSkyWeb.Plugs.RateLimit` plug, which enforces per-IP, per-session, and endpoint-specific limits. The plug delegates session lookups to the Sessions context for proper encapsulation.

**Architecture:**
- The plug checks a request against configured rules (WebAuthn endpoints) or a configurable default
- For per-session buckets (Phase 2, feature-flagged), session validation is delegated to `Sessions.get_session_id_by_uuid/1`
- This separation prevents raw database queries in the plug layer and maintains context boundaries

**Session Lookup in RateLimit Plug:**
```elixir
defp lookup_session_id(uuid) do
  EyeInTheSky.Sessions.get_session_id_by_uuid(uuid)
end
```

The `get_session_id_by_uuid/1` function validates that the UUID corresponds to an existing session and returns its integer ID. If the session does not exist, the lookup fails and the plug falls back to IP-based rate limiting.

---

## Batch Session Deletion

The `Sessions.batch_delete_sessions/1` function deletes multiple sessions in a single query, replacing the previous N+1 pattern:

**Signature:**
```elixir
def batch_delete_sessions(ids) when is_list(ids) do
  Repo.delete_all(from s in Session, where: s.id in ^ids)
end
```

**Returns:** `{deleted_count, nil}` tuple from `Repo.delete_all/1`

**Usage:**
```elixir
ids = [123, 456, 789]
{deleted, _} = Sessions.batch_delete_sessions(ids)
# deleted = 3
```

**Performance:** Consolidates N individual delete queries into a single SQL statement using an IN clause. Used by bulk selection delete handlers in `AgentLive.IndexActions` and `ProjectLive.Sessions.Actions`.

---

## Session Query Limits

All session listing functions accept optional `limit` and `offset` parameters to prevent unbounded queries:

**Default Limits:**
| Function | Default Limit | Parameter |
|----------|---------------|-----------|
| `list_sessions/1` | 1,000 | `limit: n` |
| `list_sessions_for_agent/2` | 200 | `limit: n` |
| `list_project_sessions_with_agent/2` | 500 | `limit: n`, `offset: n` |
| `list_sessions_for_scope/2` | None (callers must pass) | `limit: n`, `offset: n` |

**Usage:**
```elixir
# Default limit (1000)
Sessions.list_sessions()

# Custom limit
Sessions.list_sessions(limit: 500)

# With offset for pagination
Sessions.list_sessions_for_scope(scope, limit: 50, offset: 100)
```

All callers should use explicit limits or accept the function's default. Never call a listing function without considering result size.

### Nil Limit Safety

Query helper functions in `EyeInTheSky.QueryHelpers` (`for_session_direct/3` and `for_session_join/4`) treat `nil` limits as the default 500:

```elixir
limit_val = Keyword.get(opts, :limit) || 500
```

This prevents callers from accidentally passing `limit: nil` and fetching unbounded results. The nil-coalescing pattern ensures that missing or explicitly-nil limit options both default to 500.

---

## Zombie Session Sweep with Partial Indexes

The zombie sweep scheduler detects sessions stuck in `working` status for >30 minutes with no activity, marking them as `failed`. The query uses partial indexes on `sessions(:last_activity_at)` and `sessions(:started_at)` for efficiency.

**Schema:**
- `last_activity_at` — `:utc_datetime_usec` type (DateTime struct, not a binary string)
- `started_at` — `:utc_datetime_usec` type (DateTime struct)

**Stale Session Detection:**
The `stale?/2` function in `SessionController` accepts either a `DateTime` struct or an ISO8601 binary string and returns true if the timestamp is older than the specified minutes:

```elixir
defp stale?(%DateTime{} = dt, minutes) do
  DateTime.diff(DateTime.utc_now(), dt, :second) > minutes * 60
end

defp stale?(iso_string, minutes) when is_binary(iso_string) do
  case DateTime.from_iso8601(iso_string) do
    {:ok, dt, _} -> stale?(dt, minutes)
    _ -> false
  end
end
```

**Query Structure:**
```elixir
def list_idle_sessions_older_than(cutoff) do
  from(s in Session,
    where: s.status in ["idle", "waiting"],
    where: is_nil(s.archived_at),
    where: not is_nil(s.started_at),
    where:
      (not is_nil(s.last_activity_at) and s.last_activity_at < ^cutoff) or
        (is_nil(s.last_activity_at) and s.started_at < ^cutoff)
  )
  |> Repo.all()
end
```

**Index Design:**
Two separate OR branches allow PostgreSQL to use:
1. **`sessions(:last_activity_at)` index** — for sessions with recent activity
2. **`sessions(:started_at)` index** — for sessions that never received an activity update

A single `coalesce(last_activity_at, started_at)` expression would prevent index use and force a full table scan.

The partial indexes filter on `status IN ["idle", "waiting"]` and `archived_at IS NULL` to avoid scanning completed or archived sessions.

---

## PubSub Broadcasts for Session Updates

PubSub broadcasts for session status updates are emitted from the Sessions context via the `Sessions.Events` sub-module, not the controller layer. This keeps broadcast logic co-located with the data modifications that trigger them and keeps the web layer free of direct domain event calls.

### Broadcast Functions via Sessions.Events

All broadcast helpers are accessed through `EyeInTheSky.Sessions.Events`. As of commit 76580e6d, `Sessions.BroadcastEvents` has been deleted — its implementations are now inline in `Sessions.Events` directly (no more `defdelegate` indirection).

| Function | Events fired | Use case |
|---|---|---|
| `Sessions.broadcast_session_updated(session)` | `session_updated` | Generic status update; called after PATCH |
| `Sessions.broadcast_session_completed(session)` | `session_completed` + `session_updated` | Session marked completed |
| `Sessions.broadcast_session_waiting(session)` | `agent_stopped` + `session_updated` | Session parked to waiting |
| `Sessions.broadcast_status_side_effects(session, status)` | `agent_stopped` or `agent_working` + `session_updated` | Status PATCH with arbitrary new status |

(Note: Callers use the `Sessions.*` public API; the Events sub-module is an internal implementation detail.)

`broadcast_session_completed` and `broadcast_session_waiting` are implemented via a private helper `broadcast_with_session_updated/2` that accepts the primary event function and always appends `session_updated` (commit ffda2181):

```elixir
defp broadcast_with_session_updated(session, event_fn) do
  event_fn.(session)
  Events.session_updated(session)
end
```

### Sessions.Events Sub-Module

`Sessions.Events` contains the PubSub broadcast implementations directly. `Sessions.BroadcastEvents` was deleted in commit 76580e6d — its functions were merged into `Sessions.Events`, removing the `defdelegate` layer that previously existed:

```elixir
# Before (deleted): Sessions.Events delegated to BroadcastEvents
defdelegate broadcast_session_updated(session), to: BroadcastEvents

# After: implementations are inline in Sessions.Events
def broadcast_session_updated(session), do: Phoenix.PubSub.broadcast(...)
```

This structure keeps the Sessions context boundary clear: data mutations in `StatusTransitions`, event broadcasts in `Events`.

### Sessions.OverviewQueries Sub-Module

Complex aggregated queries used by the overview/project sessions page live in `Sessions.OverviewQueries` (file: `lib/eye_in_the_sky/sessions/queries.ex`). The module was renamed from `Sessions.Queries` to `Sessions.OverviewQueries` in commit 76580e6d to distinguish it from `Sessions.Query` (basic CRUD reads). All `defdelegate` lines in `sessions.ex` were updated accordingly.

### set_session_idle/1

`Sessions.set_session_idle/1` (implemented in `Sessions.StatusTransitions`) updates session status to `"idle"` and fires `Events.agent_stopped` on the updated struct in one call. Previously, the web layer called `update_session` then fired `agent_stopped` with the stale pre-update struct. Use this in cancel/stop handlers:

```elixir
Sessions.set_session_idle(session)
# replaces:
# Sessions.update_session(session, %{status: "idle"})
# Events.agent_stopped(session)  # was stale!
```

### Archive / Unarchive

`archive_session/1` and `unarchive_session/1` (both in `Sessions.StatusTransitions`) delegate to a private `set_archived/2` that accepts either a `DateTime` value or `nil`. Both fire `session_updated` after the DB write:

```elixir
def archive_session(%Session{} = session), do: set_archived(session, DateTime.utc_now())
def unarchive_session(%Session{} = session), do: set_archived(session, nil)

defp set_archived(%Session{} = session, value) do
  with {:ok, updated} <- update_session(session, %{archived_at: value}) do
    Events.session_updated(updated)
    {:ok, updated}
  end
end
```

**Key consequence:** All callers (controller, hooks, background jobs) use these context functions and never call `EyeInTheSky.Events` directly. The context owns the full broadcast contract for session state changes.

---

## IEx Debugging

```elixir
# List active workers
DynamicSupervisor.which_children(EyeInTheSkyWeb.Claude.SessionSupervisor)

# Find worker for a session
Registry.lookup(EyeInTheSkyWeb.Claude.Registry, {:session, "some-session-id"})

# Find worker by ref
Registry.lookup(EyeInTheSkyWeb.Claude.Registry, {:ref, some_ref})

# Get worker info
EyeInTheSkyWeb.Claude.SessionWorker.get_info(pid)

# Kill a worker to test isolation
Process.exit(pid, :kill)
```
