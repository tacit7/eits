# Background Workers

This document describes the OTP workers (GenServers) that process async jobs and background tasks.

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
