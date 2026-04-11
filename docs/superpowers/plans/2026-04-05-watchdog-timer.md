# AgentWorker Watchdog Timer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent zombie AgentWorkers by detecting when a worker is stuck in `:running` with a dead handler process and force-recovering it. The watchdog must be correlated to a specific run so stale timers from previous runs cannot kill subsequent valid runs.

**Architecture:** On each `:running` transition — including retry-initiated runs — generate `run_ref = make_ref()`, store it alongside `handler_pid`, and schedule `Process.send_after(self(), {:watchdog_check, run_ref}, timeout_ms)`. The watchdog timeout is a **safety ceiling for broken terminal reconciliation, not a maximum allowed runtime for healthy long-running jobs.**

On `{:watchdog_check, run_ref}`:
1. Match `run_ref` against `state.watchdog_run_ref` — mismatch means stale, ignore.
2. Call `Process.alive?(state.handler_pid)` — alive means legitimate slow run; rearm for the same `run_ref`.
3. Dead handler + still `:running` means zombie; trigger systemic error recovery.

Store `watchdog_timer_ref`, `watchdog_run_ref`, and `handler_pid` in state. Cancel watchdog refs and clear `handler_pid` on every exit from `:running`, but through separate, clearly-scoped paths (see Helper Boundaries below).

**Policy — Fail Closed:**
- Watchdog fires the systemic error path (`handle_systemic_error`), transitioning worker to `:failed`.
- The **current job** is marked `failed` with `failure_reason = "watchdog_timeout: Nms"`.
- **All queued jobs** are also marked `failed` — systemic path is reused intentionally. A missed completion event is sufficient reason to discard the queue; we cannot trust session state.
- Session remains recoverable; the next inbound message resets `:failed` → `:idle` per existing logic.
- Watchdog failure is distinguishable from provider/tool errors via `failure_reason` in DB and events.

**Tech Stack:** Elixir/OTP — `Process.send_after/3`, `Process.cancel_timer/1`, `Process.alive?/1`, `make_ref/0`, `Application.get_env/3`.

---

## Design Notes

### Run correlation

The timer message carries `run_ref`. A stale timer from a previous run does not match `state.watchdog_run_ref` and is ignored. `Process.cancel_timer/1` does not guarantee the message is not already in the mailbox; run correlation is the correct defense, not timer cancellation alone.

### What "zombie" means here

A zombie worker is one where the handler process is dead but the worker still believes the run is active. The watchdog recovers from that state regardless of which terminal reconciliation path was missed.

This watchdog only detects dead-handler zombies. It does not detect live-but-stalled handlers; that would require a separate progress-based timeout.

This is distinct from:
- A normal handler crash (triggers `DOWN` monitor → existing recovery)
- A provider error (arrives as `{:claude_error, ...}`)
- A slow-but-alive run (handler still alive; watchdog rearms)

### Slow-but-alive runs

If the watchdog fires and `Process.alive?(handler_pid)` is true, the run is legitimately still executing. The current timer message is already being consumed at this point — rearming by replacing `watchdog_timer_ref` with a new timer ref is sufficient; no extra cancellation is needed. The watchdog rearms for the **same `run_ref`** so stale-timer safety is preserved. A run that zombifies at minute 12 (after surviving the minute-10 check) is still caught.

### Helper boundaries (critical)

`schedule_watchdog/1` and `cancel_watchdog/1` manage **only watchdog timer fields**:
- `watchdog_timer_ref`
- `watchdog_run_ref`

They do **not** touch `handler_pid`. This is intentional.

The setup paths set `handler_pid` before calling `schedule_watchdog/1`:

```elixir
%{state | handler_pid: handler_pid, ...}
|> schedule_watchdog()
```

If `schedule_watchdog/1` cleared `handler_pid` (e.g. by calling `cancel_watchdog/1` internally), the newly assigned value would be wiped, causing `Process.alive?(state.handler_pid)` to see `nil` and always declare zombie.

`handler_pid` is managed by active-run transitions (set on start) and terminal cleanup paths (cleared explicitly). It has a different lifecycle than the watchdog timer.

### Terminal cleanup paths

Not all exits from `:running` are symmetric:

- **Normal completion** (`{:claude_complete}`): cancel watchdog, demonitor handler, clear runtime fields, transition to idle. No SDK cancel needed — Claude already exited.
- **Error/cancel paths** (`do_handle_sdk_error/2`, `:cancel` cast): cancel watchdog, cancel active SDK if needed, demonitor handler, clear runtime fields.

All paths cancel the watchdog first. Error/cancel paths additionally cancel the SDK.

### Cancel semantics

`handle_cast(:cancel, ...)` signals the provider and cancels the watchdog immediately. The remaining runtime fields (`sdk_ref`, `handler_monitor`, `handler_pid`) are cleared by the resulting terminal event path (`{:claude_error, ...}` or `DOWN`).

**Assumption:** after cancel is issued, a terminal event always arrives. If it does not — e.g. the `DOWN` message arrives with a stale monitor ref and falls through to the catch-all — those fields leak. This is an existing gap in the cancel path, not introduced here. The watchdog cannot fire after cancel (already cleared), so the session will not stay "working" indefinitely, but runtime fields persist until the next run or worker restart.

### `handler_pid` scope

`handler_pid` is stored primarily for watchdog liveness checks during active runs. It is set when starting a run and cleared by the terminal event path, not by the watchdog timer helper.

### `attempt_sdk_retry/3` and watchdog scheduling

`attempt_sdk_retry/3` starts a new active SDK run with a new handler process. It must schedule a new watchdog because `handler_pid` and `watchdog_run_ref` belong to the prior attempt. The worker is already `:running` when `attempt_sdk_retry/3` is called, so `status` does not change.

`RetryPolicy.clear_retry_timer()` is not needed here: `attempt_sdk_retry/3` is called from within active error handlers, not from a `:retry_wait` state. The retry timer is only set by `RetryPolicy.schedule_retry_start/1` when transitioning to `:retry_wait`. If the worker is `:running` and enters an error handler that calls `attempt_sdk_retry/3`, no retry timer is active.

### Interaction with RetryPolicy

- Watchdog applies only while actively `:running`.
- During `:retry_wait` backoff, no watchdog is scheduled.
- When watchdog fires systemic recovery, `handle_systemic_error` clears `current_job`, queue, and resets `retry_attempt`. Retry state is implicitly reset.

---

## File Map

| File | Change |
|------|--------|
| `lib/eye_in_the_sky/claude/agent_worker.ex` | Add `watchdog_timer_ref`, `watchdog_run_ref`, `handler_pid` to struct; add `schedule_watchdog/1`, `cancel_watchdog/1`; update `monitor_handler/1` to return PID; update all `:running` transitions including `attempt_sdk_retry/3`; add `handle_info({:watchdog_check, run_ref}, ...)` clauses |
| `lib/eye_in_the_sky/claude/agent_worker/error_classifier.ex` | Add `systemic?({:watchdog_timeout, _})` clause |
| `lib/eye_in_the_sky/agent_worker_events.ex` | Add `classify_failure_reason({:watchdog_timeout, _})` clause |
| `test/eye_in_the_sky/claude/agent_worker_test.exs` | Add watchdog expiry test + stale-timer-safety test, both tagged `:watchdog` |

---

### Task 1: Add `:watchdog_timeout` to ErrorClassifier

**Files:**
- Modify: `lib/eye_in_the_sky/claude/agent_worker/error_classifier.ex`

- [ ] **Step 1: Read the file**

```bash
cat lib/eye_in_the_sky/claude/agent_worker/error_classifier.ex
```

- [ ] **Step 2: Add the watchdog clause to `systemic?/1`**

Add as the first clause, before the catch-all:

```elixir
def systemic?({:watchdog_timeout, _timeout_ms}), do: true
```

- [ ] **Step 3: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky/claude/agent_worker/error_classifier.ex
git commit -m "feat: classify watchdog_timeout as systemic error"
```

---

### Task 2: Add failure reason classification in AgentWorkerEvents

**Files:**
- Modify: `lib/eye_in_the_sky/agent_worker_events.ex`

- [ ] **Step 1: Add `classify_failure_reason` clause**

In `classify_failure_reason/1` (line ~93-97), add before the catch-all:

```elixir
defp classify_failure_reason({:watchdog_timeout, timeout_ms}), do: "watchdog_timeout: #{timeout_ms}ms"
```

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky/agent_worker_events.ex
git commit -m "feat: classify watchdog_timeout failure reason"
```

---

### Task 3: Write failing watchdog tests

**Files:**
- Modify: `test/eye_in_the_sky/claude/agent_worker_test.exs`

Add a `describe "watchdog timer"` block. Tests are tagged `:watchdog` so `--only watchdog` works.

- [ ] **Step 1: Add expiry test**

Primary assertions are behavioral (state and DB). The `queue_updated` broadcast is secondary confirmation.

```elixir
describe "watchdog timer" do
  @tag :watchdog
  test "force-transitions worker to :failed and marks message failed when :claude_complete never arrives", ctx do
    Application.put_env(:eye_in_the_sky, :watchdog_timeout_ms, 50)
    on_exit(fn -> Application.delete_env(:eye_in_the_sky, :watchdog_timeout_ms) end)

    {_agent, session} = create_test_agent_and_session(%{}, ctx)
    Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "session:#{session.id}")

    {:ok, message} =
      EyeInTheSky.Messages.create_message(%{
        session_id: session.id,
        body: "test watchdog",
        role: "user",
        status: "pending"
      })

    assert {:ok, :started} =
             EyeInTheSky.Agents.AgentManager.send_message(session.id, "test watchdog",
               model: "haiku",
               message_id: message.id
             )

    mock_port = wait_for_mock_port(session.id)

    # Kill the mock handler so Process.alive? returns false when watchdog fires.
    # Do NOT send :claude_complete. Worker should detect the dead handler and recover.
    Process.exit(mock_port, :kill)

    # Secondary: wait for broadcast indicating queue cleared
    assert_receive {:queue_updated, []}, 500

    # Primary: message marked failed in DB
    updated = EyeInTheSky.Repo.get!(EyeInTheSky.Messages.Message, message.id)
    assert updated.status == "failed"
    assert updated.failure_reason =~ "watchdog_timeout"

    # Primary: worker no longer :running (stop button condition cleared)
    refute EyeInTheSky.Claude.AgentWorker.processing?(session.id)

    # Primary: session status updated away from "working"
    {:ok, session_after} = EyeInTheSky.Sessions.get_session(session.id)
    refute session_after.status == "working"
  end
```

- [ ] **Step 2: Add stale-timer-safety test**

Primary assertions prove run 2 is unaffected. Uses `Process.sleep/1` to allow the stale timer to arrive — this is a pragmatic timing-based compromise. The property under test (run correlation) is deterministic; the synchronization mechanism is not ideal but acceptable given the mock SDK constraints.

```elixir
  @tag :watchdog
  test "stale watchdog from previous run does not kill a subsequent valid run", ctx do
    Application.put_env(:eye_in_the_sky, :watchdog_timeout_ms, 30)
    on_exit(fn -> Application.delete_env(:eye_in_the_sky, :watchdog_timeout_ms) end)

    {_agent, session} = create_test_agent_and_session(%{}, ctx)
    Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "session:#{session.id}")

    {:ok, msg1} =
      EyeInTheSky.Messages.create_message(%{
        session_id: session.id,
        body: "run one",
        role: "user",
        status: "pending"
      })

    assert {:ok, :started} =
             EyeInTheSky.Agents.AgentManager.send_message(session.id, "run one",
               model: "haiku",
               message_id: msg1.id
             )

    mock_port_1 = wait_for_mock_port(session.id)

    # Complete run 1 normally — a stale watchdog (run_ref A) with 30ms timeout is now in-flight
    send(mock_port_1, {:claude_complete, session.id})
    assert_receive {:queue_updated, _}, 500

    # Increase timeout so run 2 stays alive through the assertion window
    Application.put_env(:eye_in_the_sky, :watchdog_timeout_ms, 10_000)

    {:ok, msg2} =
      EyeInTheSky.Messages.create_message(%{
        session_id: session.id,
        body: "run two",
        role: "user",
        status: "pending"
      })

    assert {:ok, :started} =
             EyeInTheSky.Agents.AgentManager.send_message(session.id, "run two",
               model: "haiku",
               message_id: msg2.id
             )

    _mock_port_2 = wait_for_mock_port(session.id)

    # Wait for stale watchdog from run 1 to arrive and be processed (timing-based compromise)
    Process.sleep(100)

    # Primary: run 2 must still be alive
    assert EyeInTheSky.Claude.AgentWorker.processing?(session.id)

    # Primary: message 2 must not be failed — watchdog must not have touched it
    updated2 = EyeInTheSky.Repo.get!(EyeInTheSky.Messages.Message, msg2.id)
    refute updated2.status == "failed"
    assert is_nil(updated2.failure_reason)
  end
end
```

- [ ] **Step 3: Run to verify both fail**

```bash
mix test test/eye_in_the_sky/claude/agent_worker_test.exs --only watchdog 2>&1 | tail -20
```

Expected: both tests fail (watchdog not implemented yet).

---

### Task 4: Add struct fields and helpers

**Files:**
- Modify: `lib/eye_in_the_sky/claude/agent_worker.ex`

- [ ] **Step 1: Add three fields to `defstruct`**

After `:retry_timer_ref`:

```elixir
:watchdog_timer_ref,
:watchdog_run_ref,
:handler_pid,
```

- [ ] **Step 2: Update `monitor_handler/1` to return handler PID**

```elixir
defp monitor_handler({:ok, sdk_ref, handler_pid}) do
  monitor_ref = Process.monitor(handler_pid)
  {:ok, sdk_ref, monitor_ref, handler_pid}
end

defp monitor_handler({:error, _} = error), do: error
```

- [ ] **Step 3: Add runtime-configurable timeout**

```elixir
defp watchdog_timeout_ms do
  Application.get_env(:eye_in_the_sky, :watchdog_timeout_ms, 10 * 60 * 1_000)
end
```

- [ ] **Step 4: Add `schedule_watchdog/1` and `cancel_watchdog/1`**

These helpers manage **only** `watchdog_timer_ref` and `watchdog_run_ref`. They do not touch `handler_pid` — that field is managed by active-run transitions and terminal cleanup paths.

```elixir
defp schedule_watchdog(state) do
  # Cancel any previous watchdog timer before scheduling a new one.
  # Does not clear handler_pid — that is set by the caller before schedule_watchdog is called.
  state = cancel_watchdog(state)
  run_ref = make_ref()
  timeout = watchdog_timeout_ms()
  timer_ref = Process.send_after(self(), {:watchdog_check, run_ref}, timeout)
  %{state | watchdog_timer_ref: timer_ref, watchdog_run_ref: run_ref}
end

defp cancel_watchdog(%{watchdog_timer_ref: nil} = state) do
  %{state | watchdog_run_ref: nil}
end

defp cancel_watchdog(%{watchdog_timer_ref: ref} = state) do
  Process.cancel_timer(ref)
  %{state | watchdog_timer_ref: nil, watchdog_run_ref: nil}
end
```

- [ ] **Step 5: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

---

### Task 5: Update all callers of `monitor_handler/1`

`monitor_handler/1` now returns a 4-tuple. Update every call site. All three paths that start an active SDK run must set `handler_pid` and call `schedule_watchdog/1`.

**Files:**
- Modify: `lib/eye_in_the_sky/claude/agent_worker.ex` — `admit_idle/2`, `process_next_job/1`, `attempt_sdk_retry/3`

- [ ] **Step 1: Update `admit_idle/2` (~line 488)**

`handler_pid` is set in the state map before `schedule_watchdog/1` is called. `schedule_watchdog/1` does not clear it.

```elixir
case start_sdk(state, job) do
  {:ok, sdk_ref, handler_monitor, handler_pid} ->
    Logger.info("AgentWorker: SDK started for session_id=#{state.session_id}")

    :telemetry.execute(
      [:eits, :agent, :job, :started],
      %{system_time: System.system_time()},
      %{session_id: state.session_id}
    )
    WorkerEvents.on_sdk_started(state.session_id, state.provider_conversation_id)
    Messages.mark_processing(job.context[:message_id])

    new_state =
      %{
        state
        | status: :running,
          sdk_ref: sdk_ref,
          handler_monitor: handler_monitor,
          handler_pid: handler_pid,
          current_job: job
      }
      |> RetryPolicy.clear_retry_timer()
      |> schedule_watchdog()

    {{:ok, :started}, new_state}

  {:error, reason} ->
    reason_str = inspect(reason)
    Logger.error("AgentWorker: failed to start SDK for session_id=#{state.session_id} - #{reason_str}")
    WorkerEvents.on_spawn_error(state.session_id, reason)
    {{:ok, :retry_queued}, state |> enqueue_job(job) |> RetryPolicy.schedule_retry_start()}
end
```

- [ ] **Step 2: Update `process_next_job/1` (~line 575)**

```elixir
case start_sdk(state, next_job) do
  {:ok, sdk_ref, handler_monitor, handler_pid} ->
    WorkerEvents.on_sdk_started(state.session_id, state.provider_conversation_id)
    Messages.mark_processing(next_job.context[:message_id])

    new_state =
      %{
        state
        | status: :running,
          sdk_ref: sdk_ref,
          handler_monitor: handler_monitor,
          handler_pid: handler_pid,
          current_job: next_job,
          queue: rest
      }
      |> RetryPolicy.clear_retry_timer()
      |> schedule_watchdog()

    WorkerEvents.broadcast_queue_update(state.session_id, new_state.queue)
    {:noreply, new_state}

  {:error, reason} ->
    Logger.error("Failed to start SDK for next job: #{inspect(reason)}")
    {:noreply, %{state | queue: [next_job | rest]} |> RetryPolicy.schedule_retry_start()}
end
```

- [ ] **Step 3: Update `attempt_sdk_retry/3` (~line 668)**

Status remains `:running` (already set by the calling error handler). `RetryPolicy.clear_retry_timer()` is not called here — `attempt_sdk_retry/3` is only reached from within active `:running` error handlers, not from `:retry_wait`, so no retry timer is active. Watchdog must be rescheduled because `handler_pid` changed.

**Before installing the new monitor**, demonitor the old one to avoid leaking monitor references. The old `handler_monitor` is still set in state at this point (the calling error handlers do not clear it before delegating to `attempt_sdk_retry/3`).

```elixir
case start_sdk(state, new_job) do
  {:ok, sdk_ref, handler_monitor, handler_pid} ->
    if broadcast_started,
      do: WorkerEvents.on_sdk_started(state.session_id, state.provider_conversation_id)

    demonitor_handler(state.handler_monitor)

    new_state =
      %{state | sdk_ref: sdk_ref, handler_monitor: handler_monitor, handler_pid: handler_pid, current_job: new_job}
      |> schedule_watchdog()

    {:noreply, new_state}

  {:error, start_reason} ->
    Logger.error("[#{state.session_id}] #{log_label}: #{inspect(start_reason)}")
    WorkerEvents.on_sdk_errored(state.session_id, state.provider_conversation_id)
    demonitor_handler(state.handler_monitor)
    process_next_job(%{state | status: :idle, sdk_ref: nil, handler_monitor: nil, current_job: nil})
end
```

- [ ] **Step 4: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

---

### Task 6: Cancel watchdog on all exits from `:running`

All exits cancel the watchdog first. Error/cancel paths then cancel the SDK and demonitor. Normal completion cancels the watchdog and demonitors — no SDK cancel needed since Claude already exited. `handler_pid` is cleared in all terminal paths.

**Files:**
- Modify: `lib/eye_in_the_sky/claude/agent_worker.ex`

- [ ] **Step 1: Cancel in `{:claude_complete}` handler (~line 293)**

Cancel watchdog, demonitor, clear `handler_pid` and runtime fields, transition to idle.

```elixir
Messages.mark_delivered(state.current_job && state.current_job.context[:message_id])

state = cancel_watchdog(state)
demonitor_handler(state.handler_monitor)

process_next_job(%{
  state
  | status: :idle,
    sdk_ref: nil,
    handler_monitor: nil,
    handler_pid: nil,
    current_job: nil
})
```

- [ ] **Step 2: Cancel in `do_handle_sdk_error/2`**

`do_handle_sdk_error/2` is the **sole owner** of runtime-field cleanup on error paths. It clears `handler_pid`, `sdk_ref` (via `cancel_active_sdk`), and `handler_monitor` (via `demonitor_handler`) here — not in `handle_systemic_error` or `handle_transient_error`. Those downstream functions receive state that is already cleaned.

Order: cancel watchdog → cancel SDK → demonitor → clear `handler_pid` → dispatch.

```elixir
defp do_handle_sdk_error(reason, state) do
  Logger.error("[#{state.session_id}] SDK error: #{inspect(reason)}")

  :telemetry.execute(
    [:eits, :agent, :sdk, :error],
    %{system_time: System.system_time()},
    %{session_id: state.session_id, reason: reason}
  )
  state = cancel_watchdog(state)
  cancel_active_sdk(state)
  WorkerEvents.on_sdk_errored(state.session_id, state.provider_conversation_id)
  demonitor_handler(state.handler_monitor)

  state = %{state | handler_pid: nil, sdk_ref: nil, handler_monitor: nil}

  if ErrorClassifier.systemic?(reason) do
    handle_systemic_error(state, reason)
  else
    handle_transient_error(state)
  end
end
```

- [ ] **Step 3: Cancel in `:cancel` cast (~line 210)**

Cancel watchdog. `handler_pid` is cleared on the terminal event path.

```elixir
def handle_cast(:cancel, %__MODULE__{sdk_ref: ref} = state) when not is_nil(ref) do
  Logger.info("[#{state.session_id}] Cancelling SDK process (provider=#{state.provider})")
  strategy = ProviderStrategy.for_provider(state.provider)
  strategy.cancel(ref)
  {:noreply, cancel_watchdog(state)}
end
```

- [ ] **Step 4: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

---

### Task 7: Add `handle_info({:watchdog_check, run_ref}, ...)` handler

**Files:**
- Modify: `lib/eye_in_the_sky/claude/agent_worker.ex`

Add after the `:retry_start` handlers (~line 405), before the `DOWN` handler.

- [ ] **Step 1: Add two clauses**

When the watchdog fires and the handler is still alive, the current timer message is already consumed. Rearming replaces `watchdog_timer_ref` with a new timer ref — no extra cancellation needed.

```elixir
# Watchdog fired for the current run and worker is still :running.
# Check handler liveness:
# - handler alive  → legitimate slow run; rearm watchdog for same run_ref (timer already consumed)
# - handler dead   → zombie; trigger systemic error recovery
@impl true
def handle_info(
      {:watchdog_check, run_ref},
      %__MODULE__{status: :running, watchdog_run_ref: run_ref} = state
    ) do
  timeout = watchdog_timeout_ms()

  if state.handler_pid && Process.alive?(state.handler_pid) do
    Logger.warning(
      "[#{state.session_id}] Watchdog fired after #{timeout}ms but handler still alive — slow run, rearming"
    )

    new_timer_ref = Process.send_after(self(), {:watchdog_check, run_ref}, timeout)
    {:noreply, %{state | watchdog_timer_ref: new_timer_ref}}
  else
    Logger.error(
      "[#{state.session_id}] Watchdog fired after #{timeout}ms — handler dead, worker stuck in :running, forcing recovery"
    )

    WorkerEvents.broadcast_stream_clear(state.session_id)

    do_handle_sdk_error(
      {:watchdog_timeout, timeout},
      %{
        state
        | stream: StreamAssemblerProtocol.reset(state.stream),
          watchdog_timer_ref: nil,
          watchdog_run_ref: nil
      }
    )
  end
end

# Stale watchdog (run_ref mismatch) or fired after worker already transitioned — ignore.
@impl true
def handle_info({:watchdog_check, _run_ref}, state), do: {:noreply, state}
```

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

---

### Task 8: Run tests

- [ ] **Step 1: Run watchdog tests**

```bash
mix test test/eye_in_the_sky/claude/agent_worker_test.exs --only watchdog 2>&1 | tail -30
```

Expected: both green.

- [ ] **Step 2: Run full agent_worker suite**

```bash
mix test test/eye_in_the_sky/claude/agent_worker_test.exs 2>&1 | tail -20
```

Expected: all passing.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky/claude/agent_worker.ex \
        lib/eye_in_the_sky/claude/agent_worker/error_classifier.ex \
        lib/eye_in_the_sky/agent_worker_events.ex \
        test/eye_in_the_sky/claude/agent_worker_test.exs
git commit -m "feat: add correlated watchdog timer to AgentWorker for zombie recovery"
```

---

### Task 9: Update docs

**Files:**
- Modify: `docs/AGENT_WORKER_QUEUE.md`

- [ ] **Step 1: Add Zombie Worker Recovery section**

```markdown
## Zombie Worker Recovery

A zombie worker is one where the handler process is dead but the worker still
believes the run is active. The watchdog recovers from that state regardless of
which terminal reconciliation path was missed.

This watchdog only detects dead-handler zombies. It does not detect live-but-stalled
handlers; that would require a separate progress-based timeout.

This is distinct from:
- Normal handler crash (triggers `DOWN` monitor → existing recovery)
- Provider error (arrives as `{:claude_error, ...}`)
- Slow-but-alive run (handler still alive; watchdog rearms)

**Detection:** On each active run start (`admit_idle/2`, `process_next_job/1`,
`attempt_sdk_retry/3`) the worker generates `run_ref = make_ref()`, stores it
with `handler_pid`, and schedules `Process.send_after(self(), {:watchdog_check, run_ref}, timeout_ms)`.

Default timeout: 10 minutes — a **safety ceiling for broken terminal reconciliation,
not a maximum allowed runtime for healthy long-running jobs.**
Configurable: `Application.get_env(:eye_in_the_sky, :watchdog_timeout_ms)`.

**Liveness check:** Before declaring zombie, the watchdog calls `Process.alive?(state.handler_pid)`.
If alive, the worker is just slow — watchdog rearms for the same `run_ref` with a fresh timer.
A run that zombifies at minute 12 (after surviving the minute-10 check) is still caught.

**Recovery:** Handler dead → `do_handle_sdk_error({:watchdog_timeout, ms}, state)` → classified as systemic:
- current job marked `failed`, `failure_reason = "watchdog_timeout: Nms"`
- all queued jobs also marked `failed`
- worker transitions to `:failed`
- session remains recoverable via next inbound message

**Run correlation:** Timer message carries `run_ref`. Stale timers from previous runs
do not match `state.watchdog_run_ref` and are ignored. `Process.cancel_timer/1`
alone is not enough — run correlation defends against already-queued messages.

**Helper boundaries:** `schedule_watchdog/1` and `cancel_watchdog/1` manage only
`watchdog_timer_ref` and `watchdog_run_ref`. They do not touch `handler_pid`.
`handler_pid` is set by active-run transitions and cleared by terminal cleanup paths.

**Timer lifecycle:**
- Scheduled: `admit_idle/2`, `process_next_job/1`, `attempt_sdk_retry/3` on active run start
- Rearmed: watchdog handler when handler is still alive (slow run, same run_ref)
- Cancelled (refs cleared): `{:claude_complete}`, `do_handle_sdk_error/2`, `:cancel` cast
- Does not apply during `:retry_wait` backoff
```

- [ ] **Step 2: Compile and commit**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
git add docs/AGENT_WORKER_QUEUE.md
git commit -m "docs: document watchdog timer design and run correlation in AGENT_WORKER_QUEUE.md"
```

---

## Self-Review

**Spec coverage:**
- [x] Run correlation via `{:watchdog_check, run_ref}` — Tasks 4 + 7
- [x] `handler_pid` in architecture from the start — Tasks 4 + 5
- [x] `schedule_watchdog/1` and `cancel_watchdog/1` do NOT touch `handler_pid` — Task 4 Step 4
- [x] `handler_pid` set before `schedule_watchdog` call; helper does not wipe it — Task 5 Steps 1-3
- [x] `handler_pid: nil` explicitly cleared in terminal paths (`{:claude_complete}`, `do_handle_sdk_error/2`) — Task 6 Steps 1-2
- [x] Slow-path rearms watchdog; timer already consumed note — Task 7 + Design Notes
- [x] `attempt_sdk_retry/3` schedules watchdog; no `RetryPolicy.clear_retry_timer()` with explanation — Task 5 Step 3 + Design Notes
- [x] Terminal cleanup asymmetry documented (complete vs error/cancel) — Design Notes
- [x] Zombie definition: observable state; live-but-stalled explicitly out of scope — Design Notes
- [x] Test tags `@tag :watchdog`; `--only watchdog` backed by real tags — Task 3
- [x] Stale-timer test timing compromise documented inline — Task 3 Step 2
- [x] "Safety ceiling" framing in Architecture section — Architecture paragraph
- [x] Docs include helper boundary explanation — Task 9

**Placeholder scan:** No TBDs. All code blocks are complete.

**Type consistency:**
- `monitor_handler/1` returns `{:ok, sdk_ref, monitor_ref, pid}` — all three call sites updated in Task 5
- `cancel_watchdog/1` clears `watchdog_timer_ref` + `watchdog_run_ref` only — does not touch `handler_pid`
- `schedule_watchdog/1` calls `cancel_watchdog/1` first then sets new refs — safe to call on re-entry
- `handler_pid` explicitly cleared in: `{:claude_complete}` map update, `do_handle_sdk_error/2` state rebind
