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

PubSub broadcasts for session status updates are emitted from the Sessions context (`lib/eye_in_the_sky/sessions.ex`), not the controller layer. This keeps broadcast logic co-located with the data modifications that trigger them and keeps the web layer free of direct domain event calls.

### Broadcast Functions

All broadcast helpers live in `EyeInTheSky.Sessions`:

| Function | Events fired | Use case |
|---|---|---|
| `broadcast_session_updated(session)` | `session_updated` | Generic status update; called after PATCH |
| `broadcast_session_completed(session)` | `session_completed` + `session_updated` | Session marked completed |
| `broadcast_session_waiting(session)` | `agent_stopped` + `session_updated` | Session parked to waiting |
| `broadcast_status_side_effects(session, status)` | `agent_stopped` or `agent_working` + `session_updated` | Status PATCH with arbitrary new status |

`broadcast_session_completed` and `broadcast_session_waiting` are implemented via a private helper `broadcast_with_session_updated/2` that accepts the primary event function and always appends `session_updated` (commit ffda2181):

```elixir
defp broadcast_with_session_updated(session, event_fn) do
  event_fn.(session)
  Events.session_updated(session)
end
```

### set_session_idle/1

`Sessions.set_session_idle/1` updates session status to `"idle"` and fires `Events.agent_stopped` on the updated struct in one call. Previously, the web layer called `update_session` then fired `agent_stopped` with the stale pre-update struct. Use this in cancel/stop handlers:

```elixir
Sessions.set_session_idle(session)
# replaces:
# Sessions.update_session(session, %{status: "idle"})
# Events.agent_stopped(session)  # was stale!
```

### Archive / Unarchive

`archive_session/1` and `unarchive_session/1` both delegate to a private `set_archived/2` that accepts either a `DateTime` value or `nil`. Both fire `session_updated` after the DB write:

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
