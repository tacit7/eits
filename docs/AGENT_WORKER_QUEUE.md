# AgentWorker Queue and Message Lifecycle

## Overview

`AgentWorker` is a long-lived per-session GenServer. It owns an in-memory job queue and drives the Claude/Codex process lifecycle. A normal Claude process exit does **not** terminate the worker — it transitions the worker from `:running` to `:idle` and immediately dispatches the next queued job.

```
submit_message
      │
      ▼
 worker :idle? ──yes──► start_sdk ──► mark processing ──► Claude runs
      │
      no
      │
      ▼
  enqueue job
      │
      ▼
Claude completes ──► mark delivered ──► process_next_job ──► dequeue & start_sdk
```

## Job Queue

Each call to `AgentManager.send_message/3` becomes a `Job` struct and is either:
- **Started immediately** if the worker is `:idle`
- **Enqueued** (`state.queue`) if the worker is `:running` or `:retry_wait`

The queue is in-memory only. It survives normal Claude process exits (the worker stays alive) but is lost if the worker process itself crashes or the app restarts. See [Durability](#durability).

**Max depth:** 5 jobs (`@max_queue_depth`). New submissions beyond this return `{:error, :queue_full}`.

## Message Lifecycle States

User-typed messages sent via the DM page are persisted in the `messages` table before being handed to the worker. The `status` column tracks their lifecycle:

| Status | Set by | Meaning |
|--------|--------|---------|
| `"pending"` | `Messages.send_message/1` (DM page) | Created, waiting for worker to claim |
| `"processing"` | `Messages.mark_processing/1` | Worker has started the Claude run |
| `"delivered"` | `Messages.mark_delivered/1` | Claude completed successfully |
| `"failed"` | `Messages.mark_failed/2` | Worker dropped the job; `failure_reason` set |

**DM API messages** (sent via `POST /api/v1/dm`) use `"sent"` as their initial status. They follow a different path and are not subject to the pending→processing→delivered flow.

## message_id Threading

The DB message ID is threaded from creation all the way to the job:

```
handle_send_message
  │  create_user_message → message.id
  │
  └─► AgentManager.continue_session(session_id, body, [message_id: message.id, ...])
          │
          └─► RuntimeContext.build(session_id, provider, opts)
                  │  message_id: opts[:message_id]
                  │
                  └─► AgentWorker handle_call({:submit_message, message, context})
                              │
                              └─► normalize_context(context)  ← must preserve :message_id
                                      │
                                      └─► Job.new(message, context, blocks)
                                              job.context[:message_id]
```

**Important:** `normalize_context/1` in `agent_worker.ex` rebuilds the context map explicitly. Any key not listed there is dropped. `message_id` must appear in that map or all lifecycle writes become no-ops.

## Error Paths

### Systemic errors (billing, auth, missing binary)

`handle_systemic_error/2` is called. Before clearing the queue:

1. `WorkerEvents.on_current_job_failed(state.current_job, reason)` — marks the active job's message as `"failed"` with a reason string
2. `WorkerEvents.on_queue_drained(session_id, ..., state.queue, reason)` — marks every queued job's message as `"failed"`
3. In-memory queue is set to `[]`
4. Worker transitions to `:failed` status

The worker remains alive and registered. The next `send_message` call resets it to `:idle` via `process_submit`.

**Failure reasons written to DB:**
- `"billing_error"`
- `"authentication_error"`
- `"unknown_error: <truncated msg>"`
- `"retry_exhausted"`
- `inspect(reason)` truncated to 120 chars for unclassified errors

### Transient errors

`handle_transient_error/1` marks the current job's message as `"failed"` (`"transient_error"`) and immediately calls `process_next_job/1` — the queue is preserved and the next item starts.

### Retry exhaustion

`RetryPolicy.schedule_retry_start/1` when `retry_attempt >= @max_retries`: calls `on_queue_drained` to mark all queued messages failed before zeroing the queue.

## Durability

The current queue is in-memory. Loss scenarios:

| Scenario | Queue fate | Message DB state |
|----------|-----------|-----------------|
| Claude exits normally | Preserved; next job starts | `"processing"` → `"delivered"` |
| Systemic SDK error | Cleared | All written as `"failed"` with reason |
| Retry exhausted | Cleared | All written as `"failed: retry_exhausted"` |
| Worker process crash | Lost | Stuck in `"processing"` (no handler ran) |
| App restart | Lost | Stuck in `"processing"` (no handler ran) |

Crash/restart recovery is not implemented. Messages stuck in `"processing"` after a restart can be identified with:

```sql
SELECT id, body, failure_reason, inserted_at
FROM messages
WHERE status = 'processing'
ORDER BY inserted_at;
```

## Code Locations

| File | Responsibility |
|------|---------------|
| `lib/eye_in_the_sky/claude/agent_worker.ex` | Queue logic, `normalize_context/1`, `admit_idle/2`, `handle_transient_error/1`, `handle_systemic_error/2` |
| `lib/eye_in_the_sky/claude/agent_worker/retry_policy.ex` | Retry scheduling, queue drain on exhaustion |
| `lib/eye_in_the_sky/agent_worker_events.ex` | `on_queue_drained/4`, `on_current_job_failed/2`, `classify_failure_reason/1` |
| `lib/eye_in_the_sky/messages.ex` | `mark_processing/1`, `mark_delivered/1`, `mark_failed/2` |
| `lib/eye_in_the_sky/agents/runtime_context.ex` | Builds context map; `message_id` must appear in `@known_keys` |
| `lib/eye_in_the_sky_web/live/dm_live/message_handlers.ex` | Passes `message_id: message.id` to `continue_session` |
| `test/eye_in_the_sky/messages_test.exs` | Lifecycle transition tests |

## Migration

`priv/repo/migrations/20260404233239_add_failure_reason_to_messages.exs` — adds `failure_reason varchar(255)` to `messages`.
