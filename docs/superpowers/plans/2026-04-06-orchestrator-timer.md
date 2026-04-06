# Orchestrator Timer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a backend-owned, in-memory timer per orchestrator session that sends a predefined message when it fires, surviving navigation away from the DM page.

**Architecture:** A named GenServer (`OrchestratorTimers.Server`) owns a `session_id → timer_record` map. A thin public API module (`OrchestratorTimers`) wraps it. The DM page gains a hamburger menu that replaces the current inline action buttons and adds schedule/cancel timer items. Timer state is broadcast via PubSub so the DM page updates live.

**Tech Stack:** Elixir/OTP — `GenServer`, `Process.send_after/3`, `make_ref/0`, `Process.cancel_timer/1`. Phoenix LiveView. DaisyUI modals. `EyeInTheSky.Events` PubSub module.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/eye_in_the_sky/orchestrator_timers/server.ex` | Create | GenServer: owns state, fires timers, delivers messages |
| `lib/eye_in_the_sky/orchestrator_timers.ex` | Create | Public API: thin wrapper + `default_message/0` |
| `lib/eye_in_the_sky/events.ex` | Modify | Add subscribe helper + 3 broadcast functions |
| `lib/eye_in_the_sky/application.ex` | Modify | Add Server to supervision tree |
| `lib/eye_in_the_sky_web/live/dm_live/timer_handlers.ex` | Create | Handle `schedule_timer` and `cancel_timer` LiveView events |
| `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex` | Modify | Add `@active_timer` assign + subscribe to timer topic |
| `lib/eye_in_the_sky_web/live/dm_live.ex` | Modify | Add `handle_info` clauses for 3 timer events; delegate timer events |
| `lib/eye_in_the_sky_web/components/dm_page.ex` | Modify | Add `:active_timer` attr, hamburger menu, schedule modal, timer badge |
| `test/eye_in_the_sky/orchestrator_timers_test.exs` | Create | Unit tests for Server logic |
| `test/eye_in_the_sky_web/live/dm_live_timer_test.exs` | Create | LiveView tests for menu + timer state |

---

### Task 1: Add timer PubSub helpers to Events module

**Files:**
- Modify: `lib/eye_in_the_sky/events.ex`

- [ ] **Step 1: Add the timer topic to the docstring table**

In the `@moduledoc` table at the top of `lib/eye_in_the_sky/events.ex`, add a row after the last topic line:

```
  | `"session:<id>:timer"`          | DMLive                            |
```

- [ ] **Step 2: Add subscribe helper after `unsubscribe_session_status/1`**

```elixir
@doc "Subscribe to orchestrator timer events for a session."
def subscribe_session_timer(session_id), do: sub("session:#{session_id}:timer")
```

- [ ] **Step 3: Add three broadcast functions before the private section**

```elixir
# ---------------------------------------------------------------------------
# Orchestrator timer events — topic: "session:<session_id>:timer"
# ---------------------------------------------------------------------------

@doc "An orchestrator timer was scheduled (new or replacing an existing one)."
def timer_scheduled(session_id, timer),
  do: broadcast("session:#{session_id}:timer", {:timer_scheduled, timer})

@doc "An orchestrator timer was explicitly cancelled."
def timer_cancelled(session_id),
  do: broadcast("session:#{session_id}:timer", :timer_cancelled)

@doc "An orchestrator timer fired. Payload is the rescheduled timer map (repeating) or nil (one-shot)."
def timer_fired(session_id, timer_or_nil),
  do: broadcast("session:#{session_id}:timer", {:timer_fired, timer_or_nil})
```

- [ ] **Step 4: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky/events.ex
git commit -m "feat: add timer PubSub helpers to Events module"
```

---

### Task 2: Write failing OrchestratorTimers.Server tests

**Files:**
- Create: `test/eye_in_the_sky/orchestrator_timers_test.exs`

Tests start a fresh unnamed Server per test (not the app-level named one). Delivery to fake session IDs will fail gracefully — the Server handles `{:error, _}` from `AgentManager.send_message/3`.

- [ ] **Step 1: Create the test file**

```elixir
defmodule EyeInTheSky.OrchestratorTimersTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias EyeInTheSky.OrchestratorTimers.Server

  setup do
    # Start a fresh unnamed server per test to avoid state leaking between tests.
    name = :"timer_test_#{System.unique_integer([:positive])}"
    pid = start_supervised!({Server, name: name})
    {:ok, server: pid}
  end

  describe "schedule_once/3" do
    test "creates timer state with mode :once", %{server: pid} do
      assert {:ok, :scheduled} = GenServer.call(pid, {:schedule_once, 999, 60_000, "hello"})
      record = GenServer.call(pid, {:get_timer, 999})
      assert record.mode == :once
      assert record.interval_ms == 60_000
      assert record.message == "hello"
      assert %DateTime{} = record.started_at
      assert %DateTime{} = record.next_fire_at
      assert is_reference(record.token)
    end
  end

  describe "schedule_repeating/3" do
    test "creates timer state with mode :repeating", %{server: pid} do
      assert {:ok, :scheduled} = GenServer.call(pid, {:schedule_repeating, 999, 30_000, "ping"})
      record = GenServer.call(pid, {:get_timer, 999})
      assert record.mode == :repeating
      assert record.interval_ms == 30_000
      assert record.message == "ping"
    end
  end

  describe "replace-on-reschedule" do
    test "returns :replaced and installs new timer when one already active", %{server: pid} do
      assert {:ok, :scheduled} = GenServer.call(pid, {:schedule_once, 999, 60_000, "first"})
      assert {:ok, :replaced} = GenServer.call(pid, {:schedule_once, 999, 90_000, "second"})
      record = GenServer.call(pid, {:get_timer, 999})
      assert record.message == "second"
      assert record.interval_ms == 90_000
    end
  end

  describe "cancel/1" do
    test "removes the timer from state", %{server: pid} do
      GenServer.call(pid, {:schedule_once, 999, 60_000, "test"})
      assert :ok = GenServer.call(pid, {:cancel, 999})
      assert nil == GenServer.call(pid, {:get_timer, 999})
    end

    test "is a no-op when no timer active", %{server: pid} do
      assert :ok = GenServer.call(pid, {:cancel, 999})
    end
  end

  describe "get_timer/1" do
    test "returns nil when no timer active for session", %{server: pid} do
      assert nil == GenServer.call(pid, {:get_timer, 12_345})
    end
  end

  describe "stale token" do
    test "stale timer message is ignored — state unchanged after replacement", %{server: pid} do
      # Schedule and immediately replace. The first timer's message may still be
      # in the mailbox when we replace. It must be ignored.
      GenServer.call(pid, {:schedule_once, 999, 5, "first"})
      GenServer.call(pid, {:schedule_once, 999, 60_000, "second"})
      # Give time for the stale first timer to arrive and be processed
      Process.sleep(50)
      # Second timer must still be active
      record = GenServer.call(pid, {:get_timer, 999})
      assert record != nil
      assert record.message == "second"
    end
  end

  describe "one-shot fire behavior" do
    test "removes itself from state after firing", %{server: pid} do
      GenServer.call(pid, {:schedule_once, 999, 10, "test"})
      Process.sleep(100)
      assert nil == GenServer.call(pid, {:get_timer, 999})
    end
  end

  describe "repeating fire behavior" do
    test "reschedules itself after firing", %{server: pid} do
      GenServer.call(pid, {:schedule_repeating, 999, 10, "test"})
      Process.sleep(50)
      record = GenServer.call(pid, {:get_timer, 999})
      assert record != nil
      assert record.mode == :repeating
    end
  end

  describe "delivery failure policy" do
    test "one-shot removes itself even when delivery fails (no worker for session)", %{server: pid} do
      # session_id 99999 has no AgentWorker — send_message returns error
      GenServer.call(pid, {:schedule_once, 99_999, 10, "test"})
      Process.sleep(100)
      assert nil == GenServer.call(pid, {:get_timer, 99_999})
    end

    test "repeating reschedules even when delivery fails (no worker for session)", %{server: pid} do
      GenServer.call(pid, {:schedule_repeating, 99_999, 10, "test"})
      Process.sleep(50)
      record = GenServer.call(pid, {:get_timer, 99_999})
      assert record != nil
      assert record.mode == :repeating
    end
  end
end
```

- [ ] **Step 2: Run to confirm all tests fail**

```bash
mix test test/eye_in_the_sky/orchestrator_timers_test.exs 2>&1 | tail -20
```

Expected: compile error — `EyeInTheSky.OrchestratorTimers.Server` does not exist yet.

---

### Task 3: Implement OrchestratorTimers.Server

**Files:**
- Create: `lib/eye_in_the_sky/orchestrator_timers/server.ex`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p lib/eye_in_the_sky/orchestrator_timers
```

- [ ] **Step 2: Write the Server module**

```elixir
defmodule EyeInTheSky.OrchestratorTimers.Server do
  @moduledoc """
  In-memory timer registry for orchestrator sessions.

  Manages one active timer per session. Timers outlive the DM page LiveView
  socket because this GenServer runs under the application supervisor.

  Each timer carries a unique token (make_ref/0). When Process.cancel_timer/1
  is called, the old message may already be in the mailbox — the token prevents
  stale messages from firing.
  """

  use GenServer
  require Logger

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Events

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:schedule_once, session_id, delay_ms, message}, _from, state) do
    result = if Map.has_key?(state, session_id), do: {:ok, :replaced}, else: {:ok, :scheduled}
    state = cancel_existing(state, session_id)

    token = make_ref()
    timer_ref = Process.send_after(self(), {:fire_timer, session_id, token}, delay_ms)
    now = DateTime.utc_now()

    record = %{
      token: token,
      timer_ref: timer_ref,
      mode: :once,
      interval_ms: delay_ms,
      message: message,
      started_at: now,
      next_fire_at: DateTime.add(now, delay_ms, :millisecond)
    }

    label = if result == {:ok, :replaced}, do: "replaced", else: "scheduled"
    Logger.info("[OrchestratorTimers] #{label} once session=#{session_id} delay_ms=#{delay_ms} next_fire_at=#{record.next_fire_at}")

    Events.timer_scheduled(session_id, record)
    {:reply, result, Map.put(state, session_id, record)}
  end

  @impl GenServer
  def handle_call({:schedule_repeating, session_id, interval_ms, message}, _from, state) do
    result = if Map.has_key?(state, session_id), do: {:ok, :replaced}, else: {:ok, :scheduled}
    state = cancel_existing(state, session_id)

    token = make_ref()
    timer_ref = Process.send_after(self(), {:fire_timer, session_id, token}, interval_ms)
    now = DateTime.utc_now()

    record = %{
      token: token,
      timer_ref: timer_ref,
      mode: :repeating,
      interval_ms: interval_ms,
      message: message,
      started_at: now,
      next_fire_at: DateTime.add(now, interval_ms, :millisecond)
    }

    label = if result == {:ok, :replaced}, do: "replaced", else: "scheduled"
    Logger.info("[OrchestratorTimers] #{label} repeating session=#{session_id} interval_ms=#{interval_ms} next_fire_at=#{record.next_fire_at}")

    Events.timer_scheduled(session_id, record)
    {:reply, result, Map.put(state, session_id, record)}
  end

  @impl GenServer
  def handle_call({:cancel, session_id}, _from, state) do
    state = cancel_existing(state, session_id)
    Logger.info("[OrchestratorTimers] cancelled session=#{session_id}")
    Events.timer_cancelled(session_id)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:get_timer, session_id}, _from, state) do
    {:reply, Map.get(state, session_id), state}
  end

  @impl GenServer
  def handle_call(:list_active, _from, state) do
    {:reply, Map.values(state), state}
  end

  @impl GenServer
  def handle_info({:fire_timer, session_id, token}, state) do
    case Map.get(state, session_id) do
      %{token: ^token} = record ->
        do_fire(session_id, record, state)

      nil ->
        # Timer was cancelled and state already cleaned up.
        {:noreply, state}

      _ ->
        # Stale token from a replaced or cancelled timer. Ignore.
        Logger.debug("[OrchestratorTimers] stale timer for session=#{session_id}, ignoring")
        {:noreply, state}
    end
  end

  defp do_fire(session_id, record, state) do
    Logger.info("[OrchestratorTimers] timer fired session=#{session_id} mode=#{record.mode}")

    case AgentManager.send_message(session_id, record.message, []) do
      {:ok, _} ->
        Logger.info("[OrchestratorTimers] delivery succeeded session=#{session_id}")

      {:error, reason} ->
        Logger.warning("[OrchestratorTimers] delivery failed session=#{session_id} reason=#{inspect(reason)}")
    end

    case record.mode do
      :once ->
        Events.timer_fired(session_id, nil)
        {:noreply, Map.delete(state, session_id)}

      :repeating ->
        token = make_ref()
        timer_ref = Process.send_after(self(), {:fire_timer, session_id, token}, record.interval_ms)
        now = DateTime.utc_now()

        new_record = %{
          record
          | token: token,
            timer_ref: timer_ref,
            next_fire_at: DateTime.add(now, record.interval_ms, :millisecond)
        }

        Events.timer_fired(session_id, new_record)
        {:noreply, Map.put(state, session_id, new_record)}
    end
  end

  defp cancel_existing(state, session_id) do
    case Map.get(state, session_id) do
      nil ->
        state

      %{timer_ref: ref} ->
        Process.cancel_timer(ref)
        Map.delete(state, session_id)
    end
  end
end
```

- [ ] **Step 3: Run tests**

```bash
mix test test/eye_in_the_sky/orchestrator_timers_test.exs 2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky/orchestrator_timers/server.ex \
        test/eye_in_the_sky/orchestrator_timers_test.exs
git commit -m "feat: implement OrchestratorTimers.Server GenServer with token-correlated timers"
```

---

### Task 4: Create OrchestratorTimers public API

**Files:**
- Create: `lib/eye_in_the_sky/orchestrator_timers.ex`

- [ ] **Step 1: Write the public API module**

```elixir
defmodule EyeInTheSky.OrchestratorTimers do
  @moduledoc """
  Public API for orchestrator session timers.

  One active timer per session. Timers outlive the DM page LiveView socket.
  Backed by OrchestratorTimers.Server — callers should never interact with the
  Server directly.
  """

  alias EyeInTheSky.OrchestratorTimers.Server

  @doc "The default message sent when a timer fires."
  def default_message do
    "Please check in with your team members and report their current status and any blockers."
  end

  @doc "Schedule a one-shot timer. Replaces any existing timer for the session."
  def schedule_once(session_id, delay_ms, message \\ default_message()) do
    GenServer.call(Server, {:schedule_once, session_id, delay_ms, message})
  end

  @doc "Schedule a repeating timer. Replaces any existing timer for the session."
  def schedule_repeating(session_id, interval_ms, message \\ default_message()) do
    GenServer.call(Server, {:schedule_repeating, session_id, interval_ms, message})
  end

  @doc "Cancel the active timer for a session. No-op if none active."
  def cancel(session_id) do
    GenServer.call(Server, {:cancel, session_id})
  end

  @doc "Return the active timer map for a session, or nil if none active."
  def get_timer(session_id) do
    GenServer.call(Server, {:get_timer, session_id})
  end

  @doc "Return all active timer maps."
  def list_active do
    GenServer.call(Server, :list_active)
  end
end
```

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky/orchestrator_timers.ex
git commit -m "feat: add OrchestratorTimers public API module"
```

---

### Task 5: Wire Server into supervision tree

**Files:**
- Modify: `lib/eye_in_the_sky/application.ex`

- [ ] **Step 1: Add the Server child after RateLimiter, before Endpoint**

In `lib/eye_in_the_sky/application.ex`, find:

```elixir
      # Rate limiter ETS backend for auth endpoint throttling
      EyeInTheSky.RateLimiter,
      # Start to serve requests, typically the last entry
      EyeInTheSkyWeb.Endpoint
```

Change to:

```elixir
      # Rate limiter ETS backend for auth endpoint throttling
      EyeInTheSky.RateLimiter,
      # In-memory timer registry for orchestrator sessions
      EyeInTheSky.OrchestratorTimers.Server,
      # Start to serve requests, typically the last entry
      EyeInTheSkyWeb.Endpoint
```

- [ ] **Step 2: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/eye_in_the_sky/application.ex
git commit -m "feat: add OrchestratorTimers.Server to supervision tree"
```

---

### Task 6: Add DmLive timer event handlers

**Files:**
- Create: `lib/eye_in_the_sky_web/live/dm_live/timer_handlers.ex`
- Modify: `lib/eye_in_the_sky_web/live/dm_live.ex`

- [ ] **Step 1: Create timer_handlers.ex**

```elixir
defmodule EyeInTheSkyWeb.DmLive.TimerHandlers do
  @moduledoc """
  Handles schedule_timer and cancel_timer events from the DM page.
  """

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.OrchestratorTimers

  @presets_ms %{
    "5m" => 5 * 60 * 1_000,
    "10m" => 10 * 60 * 1_000,
    "15m" => 15 * 60 * 1_000,
    "30m" => 30 * 60 * 1_000,
    "1h" => 60 * 60 * 1_000
  }

  def handle_schedule_timer(%{"mode" => mode, "preset" => preset}, socket) do
    session_id = socket.assigns.session_id
    interval_ms = Map.get(@presets_ms, preset, 15 * 60 * 1_000)
    message = OrchestratorTimers.default_message()

    case mode do
      "once" -> OrchestratorTimers.schedule_once(session_id, interval_ms, message)
      "repeating" -> OrchestratorTimers.schedule_repeating(session_id, interval_ms, message)
      _ -> OrchestratorTimers.schedule_once(session_id, interval_ms, message)
    end

    # Close the schedule modal; @active_timer updates via handle_info broadcast.
    {:noreply, assign(socket, :active_overlay, nil)}
  end

  def handle_cancel_timer(socket) do
    OrchestratorTimers.cancel(socket.assigns.session_id)
    {:noreply, socket}
  end
end
```

- [ ] **Step 2: Wire events into dm_live.ex**

Add the alias at the top of the module with the other aliases:

```elixir
alias EyeInTheSkyWeb.DmLive.TimerHandlers
```

Add three event handlers alongside the other `handle_event` clauses:

```elixir
@impl true
def handle_event("schedule_timer", params, socket),
  do: TimerHandlers.handle_schedule_timer(params, socket)

@impl true
def handle_event("cancel_timer", _params, socket),
  do: TimerHandlers.handle_cancel_timer(socket)

@impl true
def handle_event("open_schedule_timer", _params, socket) do
  {:noreply, assign(socket, :active_overlay, :schedule_timer)}
end

@impl true
def handle_event("close_schedule_modal", _params, socket) do
  {:noreply, assign(socket, :active_overlay, nil)}
end
```

- [ ] **Step 3: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web/live/dm_live/timer_handlers.ex \
        lib/eye_in_the_sky_web/live/dm_live.ex
git commit -m "feat: add DmLive timer event handlers"
```

---

### Task 7: Update DmLive mount — subscribe + @active_timer assign

**Files:**
- Modify: `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex`
- Modify: `lib/eye_in_the_sky_web/live/dm_live.ex`

- [ ] **Step 1: Add subscription in mount_state.ex**

Add to the existing alias block at the top of `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex`:

```elixir
alias EyeInTheSky.Events
```

In `setup_subscriptions/1`, add after `PubSubHelpers.subscribe_tasks()`:

```elixir
Events.subscribe_session_timer(session_id)
```

- [ ] **Step 2: Add @active_timer assign in assign_defaults/2**

In `assign_defaults/2` in `mount_state.ex`, add before `|> allow_upload(...)`:

```elixir
|> assign(:active_timer, EyeInTheSky.OrchestratorTimers.get_timer(session.id))
```

- [ ] **Step 3: Add handle_info clauses in dm_live.ex**

Add these three clauses alongside the other `handle_info` clauses in `lib/eye_in_the_sky_web/live/dm_live.ex`:

```elixir
@impl true
def handle_info({:timer_scheduled, timer}, socket) do
  {:noreply, assign(socket, :active_timer, timer)}
end

@impl true
def handle_info(:timer_cancelled, socket) do
  {:noreply, assign(socket, :active_timer, nil)}
end

@impl true
def handle_info({:timer_fired, timer_or_nil}, socket) do
  {:noreply, assign(socket, :active_timer, timer_or_nil)}
end
```

- [ ] **Step 4: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web/live/dm_live/mount_state.ex \
        lib/eye_in_the_sky_web/live/dm_live.ex
git commit -m "feat: subscribe to timer topic on mount, assign @active_timer, handle timer events"
```

---

### Task 8: UI — hamburger menu, schedule modal, timer badge

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/dm_page.ex`
- Modify: `lib/eye_in_the_sky_web/live/dm_live.ex`

- [ ] **Step 1: Add :active_timer attr to the DmPage component**

In `lib/eye_in_the_sky_web/components/dm_page.ex`, add after the `attr :reloading` line:

```elixir
attr :active_timer, :any, default: nil
```

- [ ] **Step 2: Replace desktop action buttons with unified hamburger menu**

Find the `<div class="flex items-center gap-1 flex-shrink-0">` block in the desktop header (contains Reload, Export, Notify, and the small mobile menu — starts around `<div class="flex items-center gap-1 flex-shrink-0">`). Replace the entire block with:

```heex
<div class="flex items-center gap-1 flex-shrink-0">
  <%!-- Active timer badge --%>
  <%= if @active_timer do %>
    <div class="hidden sm:flex items-center gap-1 px-2 py-1 rounded-lg bg-warning/10 text-warning text-xs font-medium">
      <.icon name="hero-clock" class="w-3.5 h-3.5" />
      <span>{if @active_timer.mode == :once, do: "Once", else: "Repeating"}</span>
    </div>
  <% end %>

  <%!-- Unified hamburger menu (desktop + mobile) --%>
  <div class="dropdown dropdown-end" id="dm-actions-menu">
    <button
      tabindex="0"
      class="btn btn-ghost btn-square w-9 h-9 text-base-content/60"
      aria-label="More options"
    >
      <.icon name="hero-ellipsis-horizontal" class="w-5 h-5" />
    </button>
    <ul
      tabindex="0"
      class="dropdown-content menu bg-base-100 rounded-box border border-base-content/10 shadow-lg z-50 p-1 w-52 text-xs"
    >
      <li>
        <button
          phx-click={JS.dispatch("dm:reload-check", to: "#dm-reload-confirm-modal")}
          class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
        >
          <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Reload
        </button>
      </li>
      <li>
        <button
          phx-click="export_jsonl"
          class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
        >
          <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Export as JSONL
        </button>
      </li>
      <li>
        <button
          phx-click="export_markdown"
          class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
        >
          <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Export as Markdown
        </button>
      </li>
      <li>
        <button
          id="dm-push-setup-btn"
          phx-hook="PushSetup"
          phx-update="ignore"
          data-push-state="disabled"
          title="Enable push notifications"
          class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
        >
          <.icon name="hero-bell" class="w-3.5 h-3.5" /> Notify
        </button>
      </li>
      <li><hr class="border-base-content/10 my-1" /></li>
      <li>
        <button
          phx-click="open_schedule_timer"
          class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
        >
          <.icon name="hero-clock" class="w-3.5 h-3.5" /> Schedule Message
        </button>
      </li>
      <%= if @active_timer do %>
        <li>
          <button
            phx-click="cancel_timer"
            class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-error/10 text-error rounded"
          >
            <.icon name="hero-x-circle" class="w-3.5 h-3.5" /> Cancel Schedule
          </button>
        </li>
      <% end %>
    </ul>
  </div>
</div>
```

- [ ] **Step 3: Replace mobile top-bar dropdown content**

Find the mobile top-bar dropdown (`<div class="dropdown dropdown-end">` that contains the tabs list + Reload + Export). Replace just the `<ul>` content with:

```heex
<ul
  tabindex="0"
  class="dropdown-content menu bg-base-100 rounded-box border border-base-content/10 shadow-lg z-50 p-1 w-52 text-xs"
>
  <%= for {tab, icon, label} <- @tabs do %>
    <li>
      <button
        phx-click="change_tab"
        phx-value-tab={tab}
        class={[
          "flex items-center gap-2 px-3 py-2 w-full text-left rounded",
          @active_tab == tab && "text-primary bg-primary/10",
          @active_tab != tab && "hover:bg-base-content/5"
        ]}
      >
        <.icon name={icon} class="w-3.5 h-3.5" /> {label}
      </button>
    </li>
  <% end %>
  <li><hr class="border-base-content/10 my-1" /></li>
  <li>
    <button
      phx-click={JS.dispatch("dm:reload-check", to: "#dm-reload-confirm-modal")}
      class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
    >
      <.icon name="hero-arrow-path" class="w-3.5 h-3.5" /> Reload
    </button>
  </li>
  <li>
    <button
      phx-click="export_markdown"
      class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
    >
      <.icon name="hero-clipboard-document" class="w-3.5 h-3.5" /> Export as Markdown
    </button>
  </li>
  <li>
    <button
      phx-click="open_schedule_timer"
      class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-base-content/5 rounded"
    >
      <.icon name="hero-clock" class="w-3.5 h-3.5" /> Schedule Message
    </button>
  </li>
  <%= if @active_timer do %>
    <li>
      <button
        phx-click="cancel_timer"
        class="flex items-center gap-2 px-3 py-2 w-full text-left hover:bg-error/10 text-error rounded"
      >
        <.icon name="hero-x-circle" class="w-3.5 h-3.5" /> Cancel Schedule
      </button>
    </li>
  <% end %>
</ul>
```

- [ ] **Step 4: Add the Schedule Message modal**

Add this dialog block immediately after the existing `dm-reload-confirm-modal` dialog, inside `<div id="dm-page">`:

```heex
<%!-- Schedule timer modal --%>
<%= if @active_overlay == :schedule_timer do %>
  <div class="modal modal-open" id="schedule-timer-modal">
    <div class="modal-box max-w-sm">
      <h3 class="font-semibold text-base mb-1">Schedule Message</h3>
      <p class="text-xs text-base-content/50 mb-4 leading-relaxed">
        Sends: "Please check in with your team members and report their current status and any blockers."
      </p>

      <div class="mb-3">
        <p class="text-xs font-medium text-base-content/60 mb-2">Once</p>
        <div class="flex flex-wrap gap-1.5">
          <%= for preset <- ["5m", "10m", "15m", "30m", "1h"] do %>
            <button
              phx-click="schedule_timer"
              phx-value-mode="once"
              phx-value-preset={preset}
              class="btn btn-sm btn-outline"
            >{preset}</button>
          <% end %>
        </div>
      </div>

      <div class="mb-4">
        <p class="text-xs font-medium text-base-content/60 mb-2">Repeating</p>
        <div class="flex flex-wrap gap-1.5">
          <%= for preset <- ["5m", "10m", "15m", "30m", "1h"] do %>
            <button
              phx-click="schedule_timer"
              phx-value-mode="repeating"
              phx-value-preset={preset}
              class="btn btn-sm btn-outline"
            >{preset}</button>
          <% end %>
        </div>
      </div>

      <div class="modal-action">
        <button phx-click="close_schedule_modal" class="btn btn-ghost btn-sm">Cancel</button>
      </div>
    </div>
    <div class="modal-backdrop" phx-click="close_schedule_modal"></div>
  </div>
<% end %>
```

- [ ] **Step 5: Pass active_timer to DmPage in dm_live.ex render**

In `lib/eye_in_the_sky_web/live/dm_live.ex` `render/1`, add `active_timer={@active_timer}` to the `<DmPage.dm_page>` call after `reloading={@reloading}`:

```heex
reloading={@reloading}
active_timer={@active_timer}
```

- [ ] **Step 6: Compile**

```bash
mix compile --warnings-as-errors 2>&1 | tail -10
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky_web/components/dm_page.ex \
        lib/eye_in_the_sky_web/live/dm_live.ex
git commit -m "feat: hamburger menu, schedule modal, and active timer badge on DM page"
```

---

### Task 9: LiveView tests

**Files:**
- Create: `test/eye_in_the_sky_web/live/dm_live_timer_test.exs`

- [ ] **Step 1: Create the test file**

```elixir
defmodule EyeInTheSkyWeb.DmLive.TimerTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Factory
  alias EyeInTheSky.OrchestratorTimers

  setup do
    agent = Factory.create_agent()
    session = Factory.create_session(agent)
    {:ok, agent: agent, session: session}
  end

  test "hamburger menu contains all five action items", %{conn: conn, session: session} do
    {:ok, _view, html} = live(conn, "/dm/#{session.uuid}")
    assert html =~ "Reload"
    assert html =~ "Export"
    assert html =~ "Notify"
    assert html =~ "Schedule Message"
    refute html =~ "Cancel Schedule"
  end

  test "Cancel Schedule appears when active timer exists on mount", %{conn: conn, session: session} do
    OrchestratorTimers.schedule_once(session.id, 60_000)
    {:ok, _view, html} = live(conn, "/dm/#{session.uuid}")
    assert html =~ "Cancel Schedule"
  after
    OrchestratorTimers.cancel(session.id)
  end

  test "Cancel Schedule not shown when no timer on mount", %{conn: conn, session: session} do
    OrchestratorTimers.cancel(session.id)
    {:ok, _view, html} = live(conn, "/dm/#{session.uuid}")
    refute html =~ "Cancel Schedule"
  end

  test "schedule_timer event closes modal and activates timer badge", %{conn: conn, session: session} do
    {:ok, view, _html} = live(conn, "/dm/#{session.uuid}")

    view |> element("button[phx-click='open_schedule_timer']") |> render_click()
    assert render(view) =~ "Schedule Message"

    view
    |> element("button[phx-click='schedule_timer'][phx-value-mode='once'][phx-value-preset='5m']")
    |> render_click()

    html = render(view)
    refute html =~ "modal-open"
    assert html =~ "hero-clock"
  after
    OrchestratorTimers.cancel(session.id)
  end

  test "cancel_timer event removes timer display", %{conn: conn, session: session} do
    OrchestratorTimers.schedule_once(session.id, 60_000)
    {:ok, view, _html} = live(conn, "/dm/#{session.uuid}")
    assert render(view) =~ "Cancel Schedule"

    view |> element("button[phx-click='cancel_timer']") |> render_click()

    html = render(view)
    refute html =~ "Cancel Schedule"
    refute html =~ "hero-clock"
  end

  test "active timer badge shown after remount", %{conn: conn, session: session} do
    OrchestratorTimers.schedule_once(session.id, 60_000)
    {:ok, _view, html} = live(conn, "/dm/#{session.uuid}")
    assert html =~ "hero-clock"
  after
    OrchestratorTimers.cancel(session.id)
  end
end
```

- [ ] **Step 2: Run LiveView tests**

```bash
mix test test/eye_in_the_sky_web/live/dm_live_timer_test.exs 2>&1 | tail -30
```

Expected: all tests pass.

- [ ] **Step 3: Run full test suite**

```bash
mix test 2>&1 | tail -10
```

Expected: all passing, no regressions.

- [ ] **Step 4: Final compile check**

```bash
mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add test/eye_in_the_sky_web/live/dm_live_timer_test.exs
git commit -m "test: add DmLive timer LiveView tests"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|-----------------|------|
| No Oban | GenServer + Process.send_after only (Tasks 3–5) |
| Works after leaving /dm | Server in supervision tree, not in LiveView (Tasks 3, 5) |
| One-shot mode | Server handle_info :once path (Task 3) |
| Repeating mode | Server handle_info :repeating path (Task 3) |
| One active timer per session | cancel_existing called before every schedule (Task 3) |
| Default message | OrchestratorTimers.default_message/0 (Task 4) |
| Hamburger menu (desktop + mobile) | dm_page.ex (Task 8) |
| Schedule Message menu item | dm_page.ex hamburger (Task 8) |
| Cancel Scheduled Message (conditional) | dm_page.ex, conditional on @active_timer (Task 8) |
| Preset durations 5m/10m/15m/30m/1h | TimerHandlers + modal (Tasks 6, 8) |
| Message preview in modal | dm_page.ex modal (Task 8) |
| Active timer badge | dm_page.ex @active_timer (Task 8) |
| Token correlation | Server make_ref() per timer, matched in handle_info (Task 3) |
| PubSub events (3 distinct) | Events module (Task 1) + Server calls (Task 3) |
| DmLive handle_info (3 clauses) | dm_live.ex (Task 7) |
| Subscribe on mount | mount_state.ex (Task 7) |
| @active_timer on mount via get_timer/1 | mount_state.ex (Task 7) |
| Supervision placement (after RateLimiter) | application.ex (Task 5) |
| Logging at each lifecycle point | Server Logger calls (Task 3) |
| Unit tests — all 8 behaviors | Tasks 2 + 3 |
| LiveView tests — 5 scenarios | Task 9 |
