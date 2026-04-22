# Claude Session Management Architecture

The Eye in the Sky web application spawns Claude Code CLI subprocesses to handle DM conversations, agent sessions, and project-scoped prompts. Session management uses a DynamicSupervisor pattern for per-session process isolation.

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
| `session_status` | `working`, `stopped`, `waiting`, `completed`, `failed` | Lifecycle hooks | Claude process lifecycle; may lag behind member_status |

**Key behavior:**
- **`member_status: done`** fires immediately when `eits tasks complete` is called, not when the session ends
- **`session_status`** reflects the Claude Code process and lags — a member can be done but still show `working`
- **Orchestrators should check `member_status`**, not `session_status`

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
| `stopped` | Stop hook | Session explicitly stopped; CLI stopped gracefully |
| `waiting` | SessionEnd hook (sdk-cli) | Headless session ended; can be resumed |
| `completed` | i-end-session skill | Interactive session finished (manually set) |
| `failed` | SessionWorker on systemic error | Billing/auth/watchdog error; session persisted to DB, Teams cleanup fired |

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

**Example use cases:**
- `waiting` + `status_reason: "awaiting resume signal"` — session paused, needs explicit resume
- Transitioning to `working` with no explicit reason clears the field automatically
- Explicit `status_reason` in a transition (e.g., `status: "waiting"` + `status_reason: "custom reason"`) is preserved

Set via `PATCH /api/v1/sessions/:uuid` with `status_reason` parameter.

**Systemic Error Handling:**
When SessionWorker encounters a systemic error (billing failure, auth error, or watchdog timeout), it calls `AgentWorkerEvents.on_session_failed/2`:
1. Streams error event to session channel
2. Overwrites session status in DB to `"failed"` (ensuring final status persists even if previous status was `"idle"`)

Implementation in `on_session_failed/2` (after deduplication fix):
```elixir
def on_session_failed(session_id, provider_conversation_id) do
  Events.stream_error(session_id, provider_conversation_id, "Systemic error — session failed")
  update_session_status(session_id, "failed")
  :ok
end
```

The function no longer fires duplicate `session_idle`/`agent_stopped` events. Previous implementation called both on successful DB update, causing broadcast storms when multiple systemic errors fired in sequence. Removed to simplify status finalization — status update alone is sufficient.

This design ensures:
- Systemic failures are distinguishable from graceful stops (UI shows red status)
- Status is written to DB (survives worker restart)
- No duplicate broadcast events from status finalization

**Status indicator styling:**
- `stopped` → Yellow left border (warning color) on session card
- `working` → Blue left border
- `failed` → Red left border
- `waiting` → Yellow left border

**Auto-completion behavior:**
- Stopped status is **not** auto-set on CLI exit
- Completed status must be set **explicitly** via i-end-session skill
- This prevents incorrect status when sessions are retried or resumed

---

## Sessions REST API

The Sessions API at `PATCH /api/v1/sessions/:uuid` and related endpoints uses `Sessions.resolve(uuid)` to support both numeric session IDs and UUIDs:

```elixir
# Both work:
PATCH /api/v1/sessions/3185                                        # numeric session ID
PATCH /api/v1/sessions/8803d56d-dbbd-4916-9ff0-155378a64a47       # UUID
```

**Endpoints using `resolve_session/1`:**
- `PATCH /api/v1/sessions/:uuid` — Update session status (lifecycle hooks)
- `POST /api/v1/sessions/:uuid/tool_event` — Record tool event
- `POST /api/v1/sessions/:uuid/end` — End session with final status
- `GET /api/v1/sessions/:uuid/context` — Load session context
- `POST /api/v1/sessions/:uuid/context` — Upsert context

This flexibility allows CLI scripts and hooks to use either the shorter numeric ID or the full UUID interchangeably.

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
- Precondition checks: `:task_not_found`, `:already_claimed` (if state is already in-progress)

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

When `eits tasks complete` is called, it marks the member as done **for the calling session only**:

**Old behavior:**
- `mark_member_done_by_session` was called for all sessions linked to the completed task
- Could mark unrelated team members (e.g., the orchestrator) as done
- Scope was too broad

**New behavior:**
- CLI passes `EITS_SESSION_UUID` (or `EITS_SESSION_ID`) as `session_id` parameter
- Controller only marks that single session's member done
- Other sessions remain unaffected

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

## Worktree Management

Agent workers use git worktrees to isolate CLI processes and prevent conflicts on concurrent spawns.

**Location:** `lib/eye_in_the_sky_web/git/worktrees.ex` (Git.Worktrees module)

**Key behaviors:**
- Worktrees reuse existing paths on repeated `prepare_session_worktree/2` calls
- Dirty state check filters untracked files (`git status --porcelain` with `??` filter)
  - Untracked files are irrelevant to worktree creation since worktrees branch from HEAD
  - Allows multiple worktrees on repos without `.gitignore` rules for `.claude/worktrees/`
- Each agent gets a dedicated worktree at `.claude/worktrees/<session-uuid>`

**Worktree fallback:**
- If worktree creation fails, agent falls back to main project directory
- Fallback is silent in non-critical paths; logged in debug contexts

---

## LiveView Safety Fixes

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
