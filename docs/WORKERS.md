# Background Workers

This document describes the OTP workers (GenServers) that process async jobs and background tasks.

## AgentWorker: Orphaned Claude Process Cleanup

When the server restarts while a Claude subprocess is still running, that orphaned process holds the Claude session lock. The next attempt to start the same session gets a `"Session ID already in use"` error from the CLI.

**Retry flow (in `agent_worker.ex`):**

1. `handle_info({:claude_error, ref, {:cli_error, msg}}, ...)` receives the error.
2. If `msg` contains `"already in use"` and `:kill_retry` is not set in the job context, the worker:
   - Calls `kill_orphaned_claude(uuid)` — runs `pkill -f <session_uuid>` to kill any process with the UUID in its argv, then sleeps 200ms.
   - Converts the job to a resume via `Job.as_resume/1`.
   - Sets `:kill_retry true` in the job context to prevent a second retry loop.
   - Retries `start_sdk/2` with the resume job.
   - On success: fires `WorkerEvents.on_sdk_started/2` and continues normally.
   - On failure: falls through to the normal error handler.
3. If `:kill_retry` is already set (second attempt), the error falls through — no infinite retry.

**Why `pkill -f <uuid>`:** Session UUIDs are unique enough that false matches are not a concern. The UUID appears in the Claude subprocess argv (`--resume <uuid>`), making it a reliable match target.

**`Job.as_resume/1`:** Sets `has_messages: true` on the job context, preserving all other context fields and message/block data. This tells the CLI layer to use `--resume` instead of a fresh start.

**Code locations:**
- `lib/eye_in_the_sky/claude/agent_worker.ex` — `handle_info` clause for `already in use`, `kill_orphaned_claude/1`
- `lib/eye_in_the_sky/claude/job.ex` — `Job.as_resume/1`
- `test/eye_in_the_sky/claude/agent_worker_test.exs` — retry and fall-through tests
- `test/eye_in_the_sky/claude/job_test.exs` — `as_resume/1` tests

**Commits:** `29f9684` (orphan kill + retry), `428b0c8` (tests + `on_sdk_started` fix)

---

## AgentWorker Idle Timeout (Supervisor Slot Management)

AgentWorker processes that remain idle with empty job queues auto-terminate after 30 minutes to prevent supervisor slot exhaustion under sustained load.

**Why:** `AgentSupervisor` has a maximum number of children. Long-running idle workers tie up slots that could be used for new agents. Without idle timeout, idle workers accumulate and new spawn requests hit `max_children` errors.

**How it works:**
1. Worker enters idle state with empty queue → `IdleTimer.maybe_schedule(state)` schedules a 30-minute timer via `Process.send_after/3`
2. If a new job arrives during the 30 minutes → timer is cancelled via `IdleTimer.cancel/1`
3. If no job arrives within 30 minutes → `:idle_timeout` message triggers `exit(:normal)`
4. Supervisor sees `:normal` exit (not a crash) and does NOT restart due to `restart: :transient` config
5. Slot is freed for a new agent spawn

**Configuration:** Hard-coded to 30 minutes via `@idle_timeout_ms :timer.minutes(30)` in the IdleTimer module. No user-facing setting (CLI idle timeout is different — see section below).

**Code locations:**
- `lib/eye_in_the_sky/claude/agent_worker.ex` — calls `IdleTimer.maybe_schedule/1` in handle_info
- `lib/eye_in_the_sky/claude/agent_worker/idle_timer.ex` — `IdleTimer` module with schedule/cancel logic
- `lib/eye_in_the_sky/claude/supervisor.ex` — `restart: :transient` configuration

**Commits:** d74450ce (idle timeout feature), error recovery integration in agent_worker error handlers

---

## Agent Process Idle Timeout

Claude and Codex agent processes have a configurable idle timeout — if the subprocess produces no output for the configured duration, it is killed and the agent worker receives an error.

**Configuration:** `cli_idle_timeout_ms` setting (Settings UI → "CLI Idle Timeout", in seconds). Stored as milliseconds.

| Value | Meaning |
|-------|---------|
| `0` | No timeout (default) — process runs indefinitely |
| `N > 0` | Kill process after N milliseconds of silence |

**Default:** `0` (no timeout). Processes run until they exit naturally.

**Timeout cascade:**
1. `EyeInTheSky.CLI.Port.handle_port_output/6` — `after idle_timeout_ms` (`:infinity` when disabled). Closes the OS port and sends `{:claude_exit, ref, :timeout}` to the caller.
2. `EyeInTheSky.SDK.MessageHandler` — maps `:timeout` → `{:claude_error, sdk_ref, :timeout}` and unregisters.
3. `EyeInTheSky.Claude.AgentWorker.do_handle_sdk_error/2` — since `:timeout` is not a systemic error (billing/auth), the worker **survives**: drops the current job and processes the next queue item.

**Code locations:**
- `lib/eye_in_the_sky/cli/port.ex` — port receive loop
- `lib/eye_in_the_sky/claude/cli.ex` — reads setting, resolves `:infinity` when value is 0
- `lib/eye_in_the_sky/codex/cli.ex` — same for Codex processes
- `lib/eye_in_the_sky/claude/agent_worker.ex` — `do_handle_sdk_error/2` recovery logic
- `lib/eye_in_the_sky_web/live/overview_live/settings.ex` — UI

---

## Systemic Error Recovery

When AgentWorker encounters a systemic error (billing/auth failure, API limits), it terminates the session and fires Teams cleanup rather than retrying.

**Systemic vs. Transient Errors:**
- **Systemic** (non-recoverable): billing/auth/quota errors — calling `on_session_failed/2` → writes `failed` status to DB, fires Teams cleanup event via PubSub
- **Transient** (recoverable): timeout, connection issues — worker survives, drops job, processes next queue item

**on_session_failed/2 behavior:**
1. Writes session status to `failed` in the database
2. Fires `on_session_failed` PubSub event to notify any Teams orchestrator or observers
3. Deduplicates events: ensures only one `session_idle` and one `agent_stopped` event fire per session (no duplicate idempotency)
4. Logs error details for debugging

**Error classification:**
- Systemic errors invoke `on_session_failed/2`
- Transient errors fall through to standard recovery (next job in queue)

**Code locations:**
- `lib/eye_in_the_sky/claude/agent_worker.ex` — `do_handle_sdk_error/2` classification logic
- `lib/eye_in_the_sky/claude/agent_worker/error_recovery.ex` — `on_session_failed/2` and deduplication
- `lib/eye_in_the_sky/worker_events.ex` — PubSub event broadcasting

**Commits:** 62933518 (systemic error handling + DB write + Teams cleanup), af425751 (deduplication fix)

---

## AgentWorker Abnormal Exit Handling

When an AgentWorker process terminates abnormally (crash, non-zero exit), it marks the associated session as `failed` and fires Teams cleanup events.

**How it works:**
1. `AgentWorker.terminate/2` is called with a reason (`:normal`, `:shutdown`, or crash reason)
2. If reason is NOT `:normal` or `:shutdown` (abnormal termination), the worker:
   - Calls `EyeInTheSky.AgentWorkerEvents.on_session_failed(session_id, pcid)`
   - Wrapped in `try/rescue` to protect against DB connection failures during shutdown
3. `on_session_failed/2` behavior (same as systemic error handler):
   - Writes session status to `failed` in the database
   - Fires `on_session_failed` PubSub event to notify Teams orchestrators
   - Deduplicates cleanup events to prevent duplicate Teams member updates
   - Logs error context for debugging

**Why this matters:** If AgentWorker crashes without going through the normal error handler (e.g., OOM, unhandled exception), the session would otherwise remain in `working` status indefinitely. This handler ensures the UI reflects reality by immediately marking the session failed.

**Error scenarios that trigger this:**
- Worker process runs out of memory (OOM)
- Unhandled exception in worker code
- BEAM VM terminating the process
- Explicit `exit/1` call (not `:normal`)

**Code locations:**
- `lib/eye_in_the_sky/claude/agent_worker.ex` — `terminate/2` clause
- `lib/eye_in_the_sky/claude/agent_worker_events.ex` — `on_session_failed/2`

**Commits:** 8af3b10a (abnormal exit cleanup on terminate)

---

## Zombie Session Sweeper

A periodic scheduler detects and cleans up sessions stuck in `working` status with no heartbeat activity, marking them as failed when their AgentWorker has died.

**Problem:** When AgentWorker crashes silently (e.g., connection lost before terminate/2 is called), the session remains in `working` status forever. The UI shows active agents that are actually dead.

**Solution:** `AgentStatus` scheduler runs every 5 minutes and sweeps zombie sessions:

1. Query for sessions in `working` status with no recent activity:
   - `last_activity_at` is NULL and `started_at` > 30 minutes old, OR
   - `last_activity_at` exists and < 30 minutes ago
   - Excludes fresh NULL sessions (gate by `started_at`) to avoid false positives
2. For each zombie:
   - Marks session status as `failed` with `status_reason: "zombie_swept"`
   - Fires `session_status/2` PubSub event (same as normal termination)
   - Marks the linked agent (if present) as `failed` to keep UI filters consistent
3. Logs warning per session and info summary

**Example:** Session created 40 minutes ago, no heartbeat activity recorded (NULL `last_activity_at`), AgentWorker process is gone → marked `failed` with reason `zombie_swept`.

**30-minute threshold:** Chosen to give long-running agents time to prove they're alive. Agents are expected to emit heartbeat activity more frequently.

**Code locations:**
- `lib/eye_in_the_sky/scheduler/agent_status.ex` — `sweep_zombie_sessions/0`
- `lib/eye_in_the_sky/sessions/session.ex` — changeset allows `status_reason: "zombie_swept"`

**Commits:** 8af3b10a (zombie sweeper + tests)

---

## Spawn Failure Tracking

When an agent spawn request fails, the error is logged to disk and recorded in the team membership table.

**Spawn Failure Logging:**
- `eits agents spawn` logs non-2xx responses to `$EITS_SPAWN_LOG` (defaults to `~/.eits/spawn-errors.log`)
- Timestamp, error code, and error message are written in line-delimited format
- Errors are echoed to stderr immediately so backgrounded callers can catch failures

**Team Member spawn_failed Status:**
- When `AgentManager.spawn_agent` encounters an error and a team is set, it calls `SpawnTeamContext.record_spawn_failure/2`
- This creates a team member row with `status: "spawn_failed"` (no linked session or agent)
- `teams status --summary` counts spawn_failed members separately from other statuses
- Orchestrators checking team status must handle spawn_failed members (retryable via spawn_agent again)

**Code locations:**
- `scripts/eits` — agents spawn error logging to `$EITS_SPAWN_LOG`
- `lib/eye_in_the_sky/agents/agent_manager.ex` — calls `SpawnTeamContext.record_spawn_failure/2`
- `lib/eye_in_the_sky/agents/agent_manager/spawn_team_context.ex` — records spawn failure as team member with nil session/agent

**Commits:** 38fe1374 (spawn failure logging and spawn_failed status), fe293c52 (spawn UX merge)

---

## SpawnTeamContext and SpawnParams Modules

Agent spawning logic was split into two focused sub-modules within `AgentManager`.

**SpawnTeamContext** (`lib/eye_in_the_sky/agents/agent_manager/spawn_team_context.ex`):
- `resolve_team(name)` — looks up a team by name, returns `{:ok, team}` or error
- `apply_context(instructions, team, member_name)` — appends team context block to instructions
- `record_spawn_failure(team, member_name)` — creates a team member row with `spawn_failed` status when spawn fails
- `maybe_join(team, agent, session, member_name)` — adds agent/session to team on successful spawn

**SpawnParams** (`lib/eye_in_the_sky/agents/agent_manager/spawn_params.ex`):
- `resolve_session_name(params, team)` — determines session name via priority: explicit `name` param > `member_name @ team_name` > `member_name` > first 250 chars of instructions
- `build(params, team)` — builds keyword opts for `create_agent` from raw HTTP spawn parameters

**Code locations:**
- `lib/eye_in_the_sky/agents/agent_manager/spawn_team_context.ex`
- `lib/eye_in_the_sky/agents/agent_manager/spawn_params.ex`

**Commits:** 13eb155f (refactor: extract SpawnTeamContext and SpawnParams)

---

## JobDispatcherWorker

Oban worker that periodically scans for due scheduled jobs and enqueues appropriate execution workers.

**Location:** `lib/eye_in_the_sky/workers/job_dispatcher_worker.ex`

**Responsibilities:**
- Registered with `Oban.Plugins.Cron`, runs every minute
- Queries `ScheduledJobs.due_jobs()` for jobs past their scheduled time
- Claims each job atomically to prevent duplicate execution
- Enqueues the appropriate execution worker (e.g., `SpawnAgentWorker`, `WorkableTaskWorker`)
- Marks the job as executed after successful enqueue

**Semantics:**
- **Enqueue failure:** releases the claim so the next tick can retry
- **Mark executed failure:** does NOT release (prevents re-enqueue if the job was already enqueued)

**Integration:**
- Replaced the older GenServer poll loop `JobEnqueuer`
- Uses `ScheduledJobs` context: `due_jobs()`, `claim_job()`, `enqueue_job()`, `mark_job_executed()`
- Fires `Oban.Job` tasks that handle the actual agent spawning or task work

**Commits:** d5b6f9c4 (jobs create/update CLI), 13eb155f (consolidate list_jobs query variants, JobDispatcherWorker refactor)

---

## MessageHandler Codex Raw Line Broadcasting

Codex raw output lines are now broadcast directly from the SDK MessageHandler, eliminating the relay through AgentWorker.

**Before (removed):**
- AgentWorker had a `handle_info({:codex_raw_line, ref, line}, ...)` clause
- MessageHandler sent `{:codex_raw_line, sdk_ref, line}` to the calling AgentWorker
- AgentWorker forwarded to `EyeInTheSky.Events.broadcast_codex_raw/2`
- Stale refs from old SDK instances were silently ignored

**After (current):**
- MessageHandler directly calls `EyeInTheSky.Events.broadcast_codex_raw(session_id, line)`
- Controlled by `forward_raw_lines` option passed to `MessageHandler.run_loop/3`
- One fewer message send and no AgentWorker involvement
- Simpler, more direct broadcast pipeline

**Code locations:**
- `lib/eye_in_the_sky/sdk/message_handler.ex` — line ~159-161, direct broadcast
- `lib/eye_in_the_sky/claude/agent_worker.ex` — removed `handle_info({:codex_raw_line, ...})` clause (line 298-308 deleted)

**Commits:** 5585f8bf (refactor: broadcast codex raw lines directly from MessageHandler, remove AgentWorker relay)

---

## DailyDigestWorker

Generates and sends daily digest notifications.

**Location:** `lib/eye_in_the_sky_web/workers/daily_digest_worker.ex`

**Responsibilities:**
- Daily scheduled job (configurable time, defaults to 9 AM)
- Aggregates recent sessions, tasks, and notes
- Broadcasts digest via PubSub or sends notifications

**Configuration:**
- Enabled/disabled via config
- Schedule time configurable via env var

**Error Handling:**
- Logs errors; does not crash the worker
- Retries on transient failures (DB connection, etc.)

---

## WorkableTaskWorker

Processes individual workable tasks assigned to this worker.

**Location:** `lib/eye_in_the_sky_web/workers/workable_task_worker.ex`

**Responsibilities:**
- Receives task details from JobDispatcherWorker or MCP tool
- Spawns Claude agent with task description and model
- Updates task status on completion

**Key Improvements:**
- **Safe project lookup:** Validates `project_id` exists before processing
- **GenServer crash handling:** Catches invalid task_ids and logs error instead of crashing
- **State cleanup:** Removes task from worker queue on success/failure

**Error Handling:**
```elixir
# Before: would crash on invalid task_id
case Tasks.get_task!(task_id) do

# After: validates and returns error atom
case Tasks.get_task_safe(task_id) do
  {:ok, task} -> process(task)
  {:error, reason} -> log_error(reason)
end
```

---

## Common Patterns

### Error Handling
- Catch errors in `handle_info/2` and `handle_call/3`; never let errors propagate
- Log error context (task_id, reason, stacktrace) for debugging
- Return safe state (`:noreply`, `:reply`) to keep worker alive

### State Management
- Keep worker state minimal (only necessary for deduplication or rate-limiting)
- Use DB for persistent state; worker state is ephemeral
- On startup, query DB to catch up if app was stopped

### Testing
- Unit test the business logic (e.g., `Tasks.mark_complete/1`)
- Integration test the worker's state transitions
- Use `ExUnit.CaptureLog` to assert log messages

---

## Supervision

All workers are supervised by `EyeInTheSkyWeb.Supervisor`:

```elixir
children = [
  ...
  {JobDispatcherWorker, []},
  {DailyDigestWorker, []},
  ...
]
```

If a worker crashes, the supervisor restarts it (after a configurable delay). One-off jobs (like WorkableTaskWorker per task) are spawned dynamically, not supervised by default.
