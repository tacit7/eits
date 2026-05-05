# Background Workers

This document describes the OTP workers (GenServers) that process async jobs and background tasks.

## AgentWorker Architecture

AgentWorker and related modules manage Claude/Codex subprocess lifecycle, queue processing, and session state. As of the 2026-04-30 refactor, these responsibilities are distributed across focused sub-modules to keep the main worker lean.

### AgentWorker.Reconciliation: Stream and Event Management

Extracted sub-module handling stream assembly, message dispatch, and session state updates.

**Responsibilities:**
- `maybe_dispatch_commands(message, state)` — routes tool-use messages to CmdDispatcher when appropriate
- `maybe_sync_provider_conversation_id(state, conversation_id)` — syncs Codex thread_id or Claude conversation_id to session.uuid for resume
- `maybe_mark_session_failed(session_id, reason)` — marks sessions failed and fires cleanup events (rarely called; most failures go through ErrorRecovery)
- `broadcast_events(events, state)` — broadcasts stream assembly events (thinking, tool_use, result) to UI via PubSub
- `start_job_trace(state)` — prepares trace logging for a new job
- `clear_job_trace(state)` — finalizes and clears the trace
- `emit(metric, metadata, state)` — emits telemetry for job completion and lifecycle events

**Code locations:**
- `lib/eye_in_the_sky/claude/agent_worker/reconciliation.ex` — all reconciliation functions

**Commits:** 3077ed6e (refactor: extract Reconciliation module)

### AgentWorker.QueueManager: Message Queue Operations

Sub-module managing job submission and queue handling.

**Responsibilities:**
- `submit(message, context, state)` — enqueues a message for processing by the running agent (exported from `process_submit/3`)
  - Wraps message in a `Job`, normalizes context, appends to queue
  - Returns `{:ok, queue_id}` or error
- Manages the job queue state machine

**Code locations:**
- `lib/eye_in_the_sky/claude/agent_worker/queue_manager.ex`

**Commits:** 3077ed6e (refactor: extract QueueManager.submit from process_submit)

---

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

## Team Member Bulk Updates

Teams.mark_member_done_by_session now uses a single atomic bulk UPDATE instead of looping per-row.

**Before (removed):**
- Queried matching team members with `where: [session_id: session_id]`
- For each member: individual `Repo.update/2` call
- O(N) roundtrips, slow broadcasts

**After (current):**
- Single `Repo.update_all/2` with `returning: true`
- One roundtrip for all members in the team
- Returns full rows so broadcasts fire directly on the result set
- Significantly faster for large teams

**Agent Spawn Upsert:**
- `find_or_create_agent/2` collapsed from 3 queries (SELECT → INSERT → SELECT) to 1
- Uses `ON CONFLICT DO UPDATE SET uuid = EXCLUDED.uuid with returning: true`
- Atomic upsert in a single roundtrip

**Code locations:**
- `lib/eye_in_the_sky/teams.ex` — `mark_member_done_by_session/2` with bulk UPDATE
- `lib/eye_in_the_sky/agents.ex` — `find_or_create_agent/2` with ON CONFLICT upsert

**Commits:** b8972bb4 (perf: bulk UPDATE and upsert optimization)

---

## Task Bulk Operations

Three new batch operations in `Tasks` module replace per-row loops with single database calls, eliminating N+1 query patterns in bulk UI actions.

### batch_archive_tasks/1

Archives multiple tasks in a single `Repo.update_all` call.

**Before (removed):**
- Queried each task with `Tasks.get_task_by_uuid!/1`
- Looped with `Enum.each`, calling `Tasks.archive_task/1` per row
- O(N) roundtrips

**After (current):**
- Accepts list of UUID strings or stringified integer IDs
- Single `Repo.update_all` with `WHERE uuid IN ^ OR id IN ^`
- Sets `archived: true, updated_at: DateTime.utc_now()`
- Returns `{archived_count, nil}`

**Code locations:**
- `lib/eye_in_the_sky/tasks.ex` — `batch_archive_tasks/1`
- `lib/eye_in_the_sky_web/live/shared/bulk_helpers.ex` — `handle_bulk_archive/2`, `handle_tasks_archive_selected/3`

**Commits:** 903f8770 (batch archive tasks), 37d739a0 (merge)

### batch_delete_tasks_with_associations/1

Deletes multiple tasks and their join-table associations in a single transaction.

**Problem:** Tasks have FK dependencies in `task_tags`, `task_sessions`, and `commit_tasks` tables. Deleting without clearing associations first violates FKs.

**Solution:**
1. Wrap the entire operation in `Repo.transaction`
2. Query matching task IDs once (using UUID/int list)
3. Delete associations first (in FK dependency order):
   - `DELETE FROM task_tags WHERE task_id IN ^task_ids`
   - `DELETE FROM task_sessions WHERE task_id IN ^task_ids`
   - `DELETE FROM commit_tasks WHERE task_id IN ^task_ids`
4. Delete tasks: `DELETE FROM tasks WHERE id IN ^task_ids`
5. Return total deleted count

**Before (removed):**
- Loop per row: `Tasks.delete_task_with_associations(task)` 
- Each call does its own association cleanup + delete — O(N) roundtrips per call
- Multiple transactions (one per task)

**After (current):**
- Single `Repo.transaction` wrapping all `delete_all` calls
- Atomic: all associations and tasks deleted together or entire operation rolls back
- One roundtrip per association table + one for tasks

**Returns:** `{deleted_count, nil}`; `{0, nil}` on empty list or transaction error.

**Code locations:**
- `lib/eye_in_the_sky/tasks.ex` — `batch_delete_tasks_with_associations/1`
- `lib/eye_in_the_sky_web/live/shared/bulk_helpers.ex` — `handle_bulk_delete/2`, `handle_tasks_delete_selected/3`

**Commits:** 1117a1ee (batch delete tasks), b2a8208b (merge)

### batch_update_task_state/2

Updates task state for multiple tasks in a single `Repo.update_all` call.

**Before (removed):**
- Loop per row with `Tasks.update_task/2` calls
- Each call: `Repo.update(changeset)` — O(N) roundtrips

**After (current):**
- Accepts list of UUID strings or stringified integer IDs, plus target `state_id`
- Single `Repo.update_all` with `WHERE uuid IN ^ OR id IN ^`
- Sets `state_id: ^state_id, updated_at: DateTime.utc_now()`
- Returns `{updated_count, nil}`

**Code locations:**
- `lib/eye_in_the_sky/tasks.ex` — `batch_update_task_state/2`
- `lib/eye_in_the_sky_web/live/shared/bulk_helpers.ex` — `handle_bulk_move/3`, `handle_tasks_state_move_selected/3`

**Commits:** 13a04aca (batch state-move tasks), 67e10685 (merge)

### Common Patterns

All three operations:
- Accept both UUID strings and stringified integer IDs (mixed lists supported)
- Use `Enum.reduce` to separate UUIDs from int IDs
- Use `WHERE condition1 IN ^ OR condition2 IN ^` to match both ID types
- Return `{count, nil}` tuples for consistency
- Return `{0, nil}` on empty lists
- Are called from `BulkHelpers` to support multi-select UI actions (archive, delete, state-move)

**Performance impact:** Reducing N+1 queries for bulk operations on 10–100 items improves UI responsiveness by 100–500ms per action.

---

## Session Batch Archive Operations

Archives multiple sessions in a single database call, eliminating N+1 query patterns in bulk archive workflows.

### batch_archive_sessions_for_project/2

Archives multiple sessions belonging to a project in a single `Repo.update_all` call.

**Before (removed):**
- Looped over selected session IDs
- Called `fetch_project_session/2` per row to fetch and validate ownership
- Called `archive_session/1` per row to archive individually
- O(N) roundtrips for fetch + archive

**After (current):**
- Accepts list of session IDs and project_id for ownership verification
- Single `Repo.update_all` with `WHERE id IN ^ AND project_id == ^project_id`
- Sets `archived_at: DateTime.utc_now()`
- Returns `{archived_count, nil}`
- Returns `{0, nil}` on empty list

**Ownership Check:** Built into the query via `project_id == ^project_id` constraint — sessions not belonging to the project are silently skipped, preventing privilege escalation.

**Integration:**
- `handle_archive_selected/2` in `ProjectLive.Sessions.Actions`
- Fetches sessions separately to get UUIDs for the `evict-dm-history` PubSub event
- Bulk archive in a single atomic call improves responsiveness for 10–100+ selected sessions

**Code locations:**
- `lib/eye_in_the_sky/sessions.ex` — `batch_archive_sessions_for_project/2`
- `lib/eye_in_the_sky_web/live/project_live/sessions/actions.ex` — `handle_archive_selected/2` integration
- `lib/eye_in_the_sky/selection.ex` — `normalize_id/1` helper for mixed ID types

**Commits:** 2c402aaf (batch archive sessions to eliminate N+1), 03d0d42c (merge)

---

## Type-Safe Form Parameter Parsing

LiveView form handlers parse HTTP parameters as strings and must convert them to typed values with safe fallback defaults.

### parse_form_int/2

Parses form parameters that should be integers (e.g., `state_id`, `priority`) with type safety and null-coalescing.

**Pattern:**
```elixir
state_id = parse_form_int(params["state_id"], 0)
priority = parse_form_int(params["priority"], 0)
```

**Behavior:**
- Accepts `params["key"]` (string or nil)
- Returns integer value if parseable, fallback default otherwise
- Prevents type errors in downstream Ecto changesets
- Used in `handle_update_task/2` (TasksHelpers) to safely coerce form input before validation

**Code locations:**
- `lib/eye_in_the_sky_web/live/shared/tasks_helpers.ex` — `handle_update_task/2`
- Used for: `state_id`, `priority` integer parameters from task form

**Commits:** 03a4ff3f (use parse_form_int for state_id/priority in handle_update_task)

---

## DM Message Delivery with Metadata

AgentWorker consumes structured JSON metadata sent alongside DM message bodies, enabling agents to receive machine-readable context without JSON appearing in the UI.

**Metadata Flow:**
1. REST API accepts optional `metadata` object in `/api/v1/dm` request alongside `body`
2. `MessagingController` auto-constructs metadata context:
   - `sender_name`: resolved from `from_session_id`
   - `from_session_uuid`, `to_session_uuid`: session UUIDs
   - `response_required`: boolean flag
3. Request metadata is merged with auto-constructed metadata (request values take precedence)
4. `DMDelivery.deliver_and_persist` passes metadata as `dm_metadata` context option to `AgentManager`
5. `RuntimeContext.build()` includes `dm_metadata` in the context map passed to Job
6. `Job.normalize_context` preserves `dm_metadata` through queue normalization
7. `ProviderStrategy.Claude` consumes metadata before starting/resuming the agent:
   - Filters out auto-populated fields (sender_name, from_session_uuid, to_session_uuid, response_required)
   - Appends remaining custom fields as JSON block to the message for the agent
   - If only auto-fields present, message is unchanged (info already in body via DMDelivery)
8. AgentWorker logs `using_metadata=true` when custom metadata is present

**Field Handling:**
- **Auto-populated fields** (sender_name, from_session_uuid, to_session_uuid, response_required) are already in the message body via DMDelivery. These are filtered out to prevent duplication.
- **Custom fields** (e.g., `action`, `pr_number`, `target_branch`) are appended to the message as a `## Metadata` JSON block, providing structured context only to the agent.
- **UI Display:** Only the `body` field is shown in the UI. Metadata is never exposed to users, enabling agents to receive machine-readable context privately.

**Example Workflow:**
```bash
curl -X POST localhost:5001/api/v1/dm \
  -H 'Content-Type: application/json' \
  -d '{
    "from_session_id": 40,
    "to_session_id": 42,
    "body": "Please review the PR",
    "metadata": {
      "action": "review",
      "pr_number": 149,
      "target_branch": "main"
    }
  }'
```

Agent receives: "DM from:alice (session:...) Please review the PR" + appended JSON with auto-fields + custom `action`, `pr_number`, `target_branch`.

**Backward Compatibility:**
Legacy DMs without metadata work unchanged. The `metadata` parameter is optional; omitting it results in only auto-populated context.

**Code locations:**
- `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex` — auto-construct and merge metadata
- `lib/eye_in_the_sky/messaging/dm_delivery.ex` — pass metadata to AgentManager
- `lib/eye_in_the_sky/agents/runtime_context.ex` — include `dm_metadata` in context type
- `lib/eye_in_the_sky/claude/job.ex` — preserve `dm_metadata` in `normalize_context`
- `lib/eye_in_the_sky/claude/agent_worker.ex` — log metadata usage
- `lib/eye_in_the_sky/claude/provider_strategy/claude.ex` — `maybe_append_metadata/2` for custom field appending
- `docs/REST_API.md` — `/api/v1/dm` endpoint reference with metadata examples

**Commits:** 94215a51 (metadata field in REST API, DMDelivery, RuntimeContext), 625fa619 (Job.normalize_context preservation, ProviderStrategy.Claude consumption, agent-facing tests)

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

## Messages.NotifyListener: Postgres LISTEN/NOTIFY Message Listener

Replaces the polling Broadcaster with an event-driven GenServer that listens for message inserts via Postgres LISTEN/NOTIFY.

**Problem solved:** The old Broadcaster polled the messages table every 2 seconds, wasting CPU and database queries on empty checks.

**Solution:** NotifyListener uses Postgrex.Notifications to subscribe to a Postgres trigger:

1. Database trigger: fires `pg_notify('messages_inserted', message_id)` on every `INSERT` to `messages` table
2. GenServer: subscribes via `Postgrex.Notifications` on a dedicated connection (separate from the Repo pool)
3. On notification: loads the row by ID and immediately broadcasts via `Events.session_new_message/2` or `Events.channel_message/2`
4. Per-message dedup: fires only once per insert, no polling overhead

**Configuration:**
- Controlled by app config: `:eye_in_the_sky, :Messages.NotifyListener, enabled: true`
- Defaults to enabled; can be disabled for testing or low-message-volume environments

**How it differs from Broadcaster:**
- **Broadcaster:** Polling, 2-second delay, CPU waste on empty checks
- **NotifyListener:** Event-driven, near-instant, zero polling overhead

**Code locations:**
- `lib/eye_in_the_sky/messages/notify_listener.ex` — GenServer, `start_notifications/0`, Postgrex trigger subscription
- Database migration: triggers on messages table INSERT

**Commits:** 3017f438 (replace polling Broadcaster with NotifyListener)

---

## Messages.BulkImporter: Optimized Batch Message Insertion

BulkImporter now uses `Repo.insert_all` for efficient batch message inserts with atomic transaction semantics and in-batch deduplication.

**Workflow:**
1. Provider (Claude, Codex) calls `BulkImporter.run/3` with a list of messages to import
2. Messages are separated into three actions via `Enum.reduce`:
   - **Updates:** messages with matching sender_role + body (unlinked) → add source_uuid via `update_message/2`
   - **Inserts:** new messages (no matching unlinked) → batch insert via `Repo.insert_all`
   - **Skips:** already known (source_uuid exists), duplicate DMs (avoid double-render), or in-batch duplicates
3. Wrapped in `Repo.transaction` for atomicity — all updates and inserts succeed or fail together
4. Per-row update errors are rescued and logged; transaction does not roll back on per-row failures
5. Return value: total count = insert_count + update_count + skip_count

**In-Batch Agent Message Deduplication:**
A `MapSet` (seen_agent_bodies) is threaded through the `Enum.reduce` accumulator to catch duplicate agent messages within the same batch before they hit the database. This closes a race window where the same agent message body could be inserted twice.

- **Mechanism:** For each non-user message, the cond clause checks `MapSet.member?(seen_agent_bodies, msg.content)` first (cheap, no DB call) before calling `agent_reply_already_recorded?` (DB round-trip).
- **User messages excluded:** User messages are intentionally NOT added to the MapSet, allowing repeated user turns (legitimate distinct prompts) to persist independently within a batch.
- **Two-layer check:** MapSet catches in-batch duplicates fast; `agent_reply_already_recorded?` catches cross-process races where `record_incoming_reply` committed before this reduce started.
- **Body tracking:** Non-user message bodies are added to the MapSet on both insert and update paths so subsequent in-batch messages with the same body are caught.

**Example scenario:** A JSONL file with three assistant messages containing identical body text:
- First message: MapSet miss on `body`, passed to DB → inserts
- Second message: MapSet hit, skipped (avoid double-render)
- Third message: MapSet hit, skipped (avoid double-render)
- Result: 1 row inserted instead of 3

**Deduplication Index:**
- Partial composite index: `(session_id, sender_role, inserted_at) WHERE source_uuid IS NULL`
- Accelerates the `find_unlinked_message/3` query for linking existing rows
- Excludes `body` column to prevent exceeding Postgres 8191-byte page limit on long messages
- Built with `CREATE INDEX CONCURRENTLY` and `@disable_ddl_transaction` to avoid blocking INSERTs

**Before (deprecated):**
- Per-row `Messages.create_message/1` call — O(N) DB roundtrips, no batch atomicity
- Single per-row rescue loop — one DB error crashed the entire import
- No in-batch dedup — identical agent messages in one JSONL file could both insert

**After (current):**
- `Repo.insert_all/3` with `on_conflict: :nothing` — O(1) roundtrip for all inserts
- Per-row updates wrapped in try/rescue — one update error doesn't crash the transaction
- Atomic: all updates and inserts commit together or fail together
- In-batch MapSet dedup — identical agent messages within one batch skip the second and subsequent inserts

**Error Handling:**
- Insert conflict (source_uuid duplicate): silently skipped via `on_conflict: :nothing`
- Update failures: logged as debug; transaction continues; count reflects only successful updates
- Transaction failure: entire batch returns 0; error logged as warning
- In-batch duplicate: skipped without DB round-trip

**Code locations:**
- `lib/eye_in_the_sky/messages/bulk_importer.ex` — `run/3`, `process_message/4`, Repo.transaction logic, MapSet threading
- `lib/eye_in_the_sky/messages.ex` — `create_message/1`, `update_message/2`, `find_unlinked_message/3`
- Database migration: dedup index creation

**Tests:** Three new test cases validate dedup behavior:
- `in-batch dedup: 3 assistant messages with same body and different uuids → 1 row`
- `mixed dedup: existing DB row + 2 in-batch messages with same body → 1 row`
- `user messages with same body in same batch are NOT deduped (both persist)`

**Commits:** 55e2e5f5 (Repo.insert_all + dedup index), 8d04610f (concurrent index + drop transaction), e7c228a9 (drop body from index), 7db631d5 (in-batch agent dedup via MapSet)

---

## Messages.IndexHealth: Monitor Message Index Status

IndexHealth provides query access to Postgres index validity for the messages table, surfacing BulkImporter health issues.

**Motivation:** When the dedup index build fails or becomes invalid (e.g., due to a botched migration), BulkImporter performance degrades silently. IndexHealth exposes this via telemetry.

**API:**
- `list_message_indexes()` — returns `{:ok, [index_row]}` or `{:error, reason}`
  - Each row: `%{name: "index_name", valid: true|false, ready: true|false}`
  - Queries `pg_index` and `pg_class` to inspect index metadata
- `invalid_indexes()` — returns list of indexes where `valid == false` or `ready == false`
  - Used for health checks; empty list = all healthy

**Integration with BulkImporter:**
- Can be called before/after imports to verify dedup index is ready
- Telemetry handler can emit alerts if indexes become invalid

**Code locations:**
- `lib/eye_in_the_sky/messages/index_health.ex` — `list_message_indexes/0`, `invalid_indexes/0`

**Commits:** ae0c666a (surface BulkImporter failures via telemetry + IndexHealth)

---

## DailyDigestWorker

Generates and sends daily digest notifications.

**Location:** `lib/eye_in_the_sky/workers/daily_digest_worker.ex`

**Responsibilities:**
- Daily scheduled job (configurable time, defaults to 9 AM)
- Aggregates recent sessions, tasks, and notes
- Broadcasts digest via PubSub or sends notifications
- Calls `EyeInTheSky.Events.jobs_updated()` directly on success and failure (no private `broadcast/0` helper)

**Configuration:**
- Enabled/disabled via config
- Schedule time configurable via env var

**Error Handling:**
- Logs errors; does not crash the worker
- Retries on transient failures (DB connection, etc.)

**Commits:** b0885aa0 (inline broadcast: remove private broadcast/0, call Events.jobs_updated() directly)

---

## WorkableTaskWorker

Processes individual workable tasks assigned to this worker.

**Location:** `lib/eye_in_the_sky/workers/workable_task_worker.ex`

**Responsibilities:**
- Receives task details from JobDispatcherWorker or MCP tool
- Spawns Claude agent with task description and model
- Updates task status on completion
- Calls `EyeInTheSky.Events.jobs_updated()` directly on all exit paths (no private `broadcast/0` helper)

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

**Commits:** b0885aa0 (inline broadcast: remove private broadcast/0, call Events.jobs_updated() directly)

---

## Queue Commands: `eits queue status` and `eits queue flush`

Two new CLI commands for managing the local annotation queue in headless/spawned agent workflows.

**`eits queue status`**
- Prints pending annotation count from `~/.eits/pending-annotations.log`
- Shows per-task summary: which tasks are awaiting annotation
- Useful for diagnosing orchestrator backlog or stalled agents
- Exit code: 0 if queue is empty, 1 if pending items exist

**`eits queue flush`**
- Replays pending annotations from `~/.eits/pending-annotations.log` to the EITS backend
- Drops successfully delivered entries (removes from log)
- Keeps failed entries (appends failure reason to log for debugging)
- Exit code: 0 if all entries were successfully flushed, 1 if any remain after retry

**Context:**
- Annotations are buffered locally by `eits tasks annotate` when the backend is unavailable
- Flush is typically called at agent shutdown to ensure all work is recorded
- Status can be polled to prevent orchestrator from waiting on stalled agents

**Code locations:**
- `scripts/eits` — `queue status` and `queue flush` subcommand implementations

**Commits:** 017b0a3e (add eits queue status/flush + orchestrator rate-limit bump)

---

## Orchestrator Rate Limiting

The RateLimit plug now recognizes orchestrator traffic and applies a separate, higher rate-limit ceiling.

**Why:** Orchestrators spawn many agents in parallel and coordinate teams across multiple concurrent spawns. Generic per-IP rate limits would starve orchestrator traffic while other users consume the same bucket.

**How it works:**
1. Request carries `x-eits-role: orchestrator` header (set by orchestrator CLI or server)
2. RateLimit plug checks for this header and uses a separate bucket keyed on the role
3. Orchestrator bucket: 5x default burst ceiling, same refill rate
4. Regular user traffic: uses the standard per-IP bucket (unchanged)
5. Buckets are independent — orchestrator traffic doesn't consume the user IP's quota

**Bucket configuration:**
- Default burst: `default_burst` from config (e.g., 100 req/sec)
- Orchestrator burst: `5 * default_burst` (e.g., 500 req/sec)
- Refill rate: same as default (refill throttle is unchanged)

**Code locations:**
- `lib/eye_in_the_sky_web/plugs/rate_limit.ex` — header detection, separate bucket keying, 5x burst ceiling
- Tests: `test/eye_in_the_sky_web/plugs/rate_limit_test.exs`

**Commits:** 017b0a3e (add eits queue status/flush + orchestrator rate-limit bump)

---

## Session Token/Cost Caching

Sessions cache total token and cost metrics on the session row to avoid expensive aggregate scans.

**Architecture:**
1. **Cache columns:** `sessions.total_tokens` (integer) and `sessions.total_cost_usd` (float), both NOT NULL with DEFAULT 0 / 0.0
2. **Atomic increment:** `Sessions.increment_usage_cache(session_id, tokens, cost)` does a single `UPDATE .. inc` on the session row
3. **Cache-first reads:** `Messages.Aggregations.total_tokens_for_session/1` and `total_cost_for_session/1` read the cached value first (O(1))
   - Fall back to full aggregate scan over messages only when cached value is nil (pre-migration sessions)
4. **Update trigger:** `Messages.create_message/1` and `create_channel_message/1` call `maybe_increment_session_cache/1` after each successful insert when usage metadata is present
   - Extracts `input_tokens`, `output_tokens`, and `total_cost_usd` from message metadata
   - Calls `Sessions.increment_usage_cache/3` atomically

**Benefits:**
- O(1) latency for session usage queries (no table scans)
- Backward compatible: pre-cache sessions fall back to aggregate scan automatically
- Atomic updates prevent read-modify-write races

**Code locations:**
- `lib/eye_in_the_sky/sessions.ex` — `increment_usage_cache/3`
- `lib/eye_in_the_sky/messages.ex` — `maybe_increment_session_cache/1` and helper extraction functions
- `lib/eye_in_the_sky/messages/aggregations.ex` — `total_tokens_for_session/1`, `total_cost_for_session/1` with cache-first logic
- `lib/eye_in_the_sky/sessions/session.ex` — field schema additions
- Migration: `20260501110334_add_token_cost_cache_to_sessions.exs`

**Commits:** 819b61e9 (add session token/cost cache columns and increment helper)

---

## Channel Message Error Handling

Errors in message routing no longer crash LiveView when a session is deleted or message insert fails.

**Before (removed):**
- `route_to_members/5` in channel_helpers.ex called `Messages.send_message/1` and `AgentManager.send_message/2` directly
- If session FK was violated (session deleted), `Ecto.ConstraintError` raised and killed the LiveView process
- No error recovery — message loss

**After (current):**
1. `route_to_members/5` wraps `Messages.send_message/1` in a case statement
   - `{:ok, _message}` — continues to `AgentManager.send_message/2` as normal
   - `{:error, changeset}` — logs error with session_id and changeset errors, skips AgentManager call
2. `Message.changeset/2` declares `foreign_key_constraint(:session_id, name: "messages_session_id_fkey")`
   - Converts FK violations to `{:error, changeset}` instead of raising
3. LiveView GenServer survives message errors; other messages in the batch continue

**Code locations:**
- `lib/eye_in_the_sky_web/live/chat_live/channel_helpers.ex` — `route_to_members/5` error handling
- `lib/eye_in_the_sky/messages/message.ex` — foreign_key_constraint declaration

**Commits:** 4b849cb9 (audit fixes: FK constraint + channel error handling)

---

## Database Index Optimization

Index builds are now non-blocking and include critical missing indexes for faster queries.

**Concurrent Index Builds:**
- All CREATE INDEX statements use `concurrently: true` and `@disable_ddl_transaction true` flags
- Prevents SHARE locks that block writes during the build
- Indexes: sessions(project_id), messages(parent_message_id), sessions(last_activity_at), sessions(started_at), agents(pending_status)

**New Indexes:**
- `notes(parent_id) WHERE parent_type = 'task'` — partial index for task-scoped note queries (mirrors project scope index)
- `iam_decisions(winning_policy_id) WHERE winning_policy_id IS NOT NULL` — accelerates policy audit queries
- `iam_decisions(project_id) WHERE project_id IS NOT NULL` — accelerates project-scoped audit queries

**Query Optimization:**
- `Sessions.list_idle_sessions_older_than/1` replaced COALESCE fragment with explicit OR branches
  - `(NOT NULL last_activity_at AND last_activity_at < cutoff) OR (NULL last_activity_at AND started_at < cutoff)`
  - Allows PG to use both `last_activity_at` and `started_at` indexes instead of falling back to table scan

**Code locations:**
- Migration `20260501053649` — concurrent index creation and @disable_ddl_transaction flags
- Migration `20260501120000` — notes task index and IAM FK indexes
- `lib/eye_in_the_sky/sessions.ex` — `list_idle_sessions_older_than/1` query optimization

**Commits:** 4b849cb9 (audit fixes: index optimization and query rewrites)

---

## Oban Worker PubSub Convention

Worker modules call `EyeInTheSky.Events.jobs_updated()` directly at each exit point. There is no private `broadcast/0` helper in any worker.

**Affected modules:**
- `WorkableTaskWorker` — 4 call sites (success, no-work, error, rescued exception)
- `DailyDigestWorker` — 2 call sites (success, error)
- `SpawnAgentWorker` — 2 call sites (success, error)
- `MixTaskWorker` — 2 call sites (success, error)

**Why removed:** The one-liner `defp broadcast do EyeInTheSky.Events.jobs_updated() end` added an indirection layer with no reuse benefit. Direct calls are clearer and eliminate the need to trace the helper.

**Commits:** b0885aa0 (refactor: inline broadcast() calls in worker modules), 9f97fc08 (merge)

---

## Tasks.Poller DB Optimization

`EyeInTheSky.Tasks.Poller` is a GenServer that detects task table mutations and broadcasts change events. Two optimizations reduce DB load significantly.

**Merged query:**
- Before: two separate queries per poll cycle — `SELECT MAX(updated_at) FROM tasks` and `SELECT COUNT(*) FROM tasks` — each a full sequential scan.
- After: single `SELECT MAX(updated_at), COUNT(*) FROM tasks` via `get_task_snapshot/0` — one round-trip per cycle.

**Increased poll interval:**
- Before: `@poll_interval 2_000` (2 seconds)
- After: `@poll_interval 5_000` (5 seconds)
- Combined effect: 2.5x fewer DB executions per minute. At 2s with two queries, Postgres was logging ~1.24M calls each in `pg_stat_statements`.

**New indexes (migration `20260502064045`):**
- `tasks_updated_at_index ON tasks (updated_at DESC)` — turns the `MAX(updated_at)` from a sequential scan into a 1-block backward index scan.
- `sessions_active_started_at_idx ON sessions (started_at DESC) WHERE archived_at IS NULL` — partial index matching the dominant `list_sessions` query filter; the existing non-partial `sessions_started_at_index` had 0 scans because queries always include `WHERE archived_at IS NULL`.
- Both indexes are created `CONCURRENTLY` with `@disable_ddl_transaction true` to avoid locking hot tables.

**Code locations:**
- `lib/eye_in_the_sky/tasks/poller.ex` — `get_task_snapshot/0`, `@poll_interval`
- `priv/repo/migrations/20260502064045_add_tasks_updated_at_and_sessions_active_indexes.exs`

**Commits:** a891c595 (Reduce Tasks.Poller DB load: merge queries, increase interval, add indexes)

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
