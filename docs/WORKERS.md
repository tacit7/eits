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

## JobDispatcherWorker

Periodically scans for workable tasks and spawns appropriate agents.

**Location:** `lib/eye_in_the_sky_web/workers/job_dispatcher_worker.ex`

**Responsibilities:**
- Poll the `tasks` table for tasks tagged as "workable" (tag_id 421, 422)
- Spawn a new agent for each workable task
- Pass task ID and model (haiku/sonnet) to the agent

**Configuration:**
- Starts automatically on app boot via `Supervisor`
- Interval: configurable, defaults to every 30 seconds

**Integration:**
- Uses `Agents.spawn_agent/3` context function
- Reads task tags from `task_tags` join table

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
