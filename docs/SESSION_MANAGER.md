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

## Session Status Lifecycle

Session status is set by lifecycle hooks and reflects the CLI process state:

| Status | Set By | Meaning |
|---|---|---|
| `working` | UserPromptSubmit hook | Claude Code is processing a message |
| `stopped` | Stop hook | Session explicitly stopped; CLI stopped gracefully |
| `waiting` | SessionEnd hook (sdk-cli) | Headless session ended; can be resumed |
| `completed` | i-end-session skill | Interactive session finished (manually set) |
| `failed` | SessionWorker on systemic error | Billing/auth/watchdog error; session persisted to DB, Teams cleanup fired |

**Systemic Error Handling:**
When SessionWorker encounters a systemic error (billing failure, auth error, or watchdog timeout), it calls `AgentWorkerEvents.on_session_failed/2`:
1. Streams error event to session channel
2. Overwrites session status in DB to `"failed"` (ensuring final status persists even if previous status was `"idle"`)
3. Fires Teams cleanup events (_no_ duplicate `session_idle`/`agent_stopped` calls — deduped to avoid broadcast storms)

This design ensures:
- Systemic failures are distinguishable from graceful stops (UI shows red status)
- Teams are notified once per failure (not broadcast duplication)
- Status is written to DB (survives worker restart)

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
