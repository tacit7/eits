# Orchestrator Timer — Design Spec

**Date:** 2026-04-06

## Goal

Add a backend-owned timer for orchestrator sessions that continues working after the user leaves the DM page. When the timer fires, it sends a predefined message to the session (e.g., "Please check in with your team members and report their current status and any blockers.").

## Constraints

- No Oban
- Works after leaving `/dm`
- One-shot and repeating modes
- One active timer per session
- Default message only for now (no custom message editor)
- Triggered from the DM page hamburger menu
- Does **not** need to survive an app restart

---

## Architecture

### New modules

**Public API:**
```
EyeInTheSky.OrchestratorTimers
```

**GenServer implementation:**
```
EyeInTheSky.OrchestratorTimers.Server
```

`OrchestratorTimers` is the boundary used by LiveView and hides all GenServer details. `Server` owns state, fires timers, and delivers messages.

### Why not `AgentWorker` or `DmLive`

- Timer must outlive the LiveView socket — it cannot live in `DmLive`
- Timer lifecycle is independent of agent run lifecycle — mixing it into `AgentWorker` adds unrelated state to an already complex FSM
- A single registry GenServer is simple, auditable, and easy to query

---

## State Model

One map entry per session with an active timer:

```elixir
%{
  session_id => %{
    token: reference(),        # stale-message guard
    timer_ref: reference(),    # Process.send_after ref
    mode: :once | :repeating,
    interval_ms: integer(),
    message: String.t(),
    started_at: DateTime.t(),
    next_fire_at: DateTime.t()
  }
}
```

---

## Public API

```elixir
OrchestratorTimers.schedule_once(session_id, delay_ms, message \\ default_message())
OrchestratorTimers.schedule_repeating(session_id, interval_ms, message \\ default_message())
OrchestratorTimers.cancel(session_id)
OrchestratorTimers.get_timer(session_id)   # returns nil | timer_map — never {:ok, _} or {:error, _}
OrchestratorTimers.list_active()           # returns [timer_map]
OrchestratorTimers.default_message()       # defined in OrchestratorTimers (public API module, not Server)
```

**Default message:**
```
"Please check in with your team members and report their current status and any blockers."
```

`get_timer/1` returns `nil` when no timer is active for the session. DmLive mount assigns:
```elixir
assign(socket, :active_timer, OrchestratorTimers.get_timer(session_id))
```

The assign key is `@active_timer` throughout the LiveView and templates.

---

## Timer Semantics

### One-shot

1. Schedule timeout
2. On fire: send message, remove timer from state

### Repeating

1. Schedule timeout
2. On fire: send message, reschedule at `now + interval_ms`, update `next_fire_at`
3. Keep active until explicitly cancelled or replaced

### Replace-on-reschedule

If a timer is already active for a session and a new one is scheduled:
- Cancel the existing timer ref
- Replace state with new timer
- Return `{:ok, :replaced}`

Do not reject. Rejecting creates pointless UI friction.

---

## Critical Safety: Timer Correlation

`Process.cancel_timer/1` does not guarantee the old timeout message is not already in the mailbox. Every timer carries a unique token:

```elixir
token = make_ref()
timer_ref = Process.send_after(self(), {:fire_timer, session_id, token}, delay_ms)
```

On `{:fire_timer, session_id, token}`:
1. Look up current state for `session_id`
2. Verify stored token matches incoming token
3. Ignore if mismatch (stale message from replaced/cancelled timer)

---

## Delivery Behavior

When a timer fires:

1. Validate token matches — ignore if stale
2. Call `AgentManager.send_message(session_id, message, [])` — actual arity is `/3` with `opts \\ []`; pass no opts
3. On success: clear (one-shot) or reschedule (repeating)
4. On failure:
   - One-shot: remove timer, log failure
   - Repeating: reschedule anyway, log failure
   - No backoff on repeating delivery failure. This is intentional: scheduling and delivery are separate concerns. A transient delivery failure should not permanently kill a repeating reminder. Expect log noise if the target session is gone for extended periods.

---

## PubSub Events

Broadcast via the existing `EyeInTheSky.Events` module. Three distinct functions matching the existing naming conventions. **Never call `Phoenix.PubSub` directly.**

**Topic:** `"session:<session_id>:timer"`

**Subscribe helper** (add to `Events`):
```elixir
def subscribe_session_timer(session_id), do: sub("session:#{session_id}:timer")
```

**Broadcast functions** (add to `Events`):
```elixir
def timer_scheduled(session_id, timer),
  do: broadcast("session:#{session_id}:timer", {:timer_scheduled, timer})

def timer_cancelled(session_id),
  do: broadcast("session:#{session_id}:timer", :timer_cancelled)

def timer_fired(session_id, timer_or_nil),
  do: broadcast("session:#{session_id}:timer", {:timer_fired, timer_or_nil})
```

**DmLive `handle_info` clauses** (three patterns, not one):
```elixir
def handle_info({:timer_scheduled, timer}, socket), do: ...
def handle_info(:timer_cancelled, socket), do: ...
def handle_info({:timer_fired, timer_or_nil}, socket), do: ...
```

Add topic to the `Events` module docstring topic table:
```
| `"session:<id>:timer"` | DMLive |
```

---

## UI Changes

### Replace inline DM action buttons

This applies to **both desktop and mobile**. The current `[Reload | Export | Notify]` buttons (desktop header) and the existing mobile kebab menu (`hero-ellipsis-vertical`) are unified into a single hamburger/kebab menu component used at all breakpoints.

Menu items:
- Reload
- Export
- Notify
- Schedule Message
- Cancel Scheduled Message *(only shown when `@active_timer` is not nil)*

### Schedule Message UI

Simple modal or inline panel. No enterprise scheduler nonsense.

Fields:
- **Mode:** once / repeating (toggle or radio)
- **Duration:** preset picker — 5 min, 10 min, 15 min, 30 min, 1 hour
- **Message preview:** read-only, shows `default_message()` text

### Active timer display

When `@active_timer` is not nil, the DM header or menu shows:
- Mode (once / repeating)
- Next fire time (absolute, from `next_fire_at`)
- Countdown (client-side rendering from `next_fire_at`; backend state is authoritative — `next_fire_at` is advisory and may drift slightly from actual fire time)

On mount, DM page assigns `@active_timer` via `OrchestratorTimers.get_timer(session_id)`.

---

## Event Flow

### Schedule

1. User opens DM menu → picks "Schedule Message"
2. User selects mode and duration
3. LiveView sends `schedule_timer` event
4. Backend calls `OrchestratorTimers.schedule_once/3` or `schedule_repeating/3`
5. Server cancels existing timer if present, stores new state
6. Server broadcasts `timer_updated` event
7. LiveView updates assigns from broadcast

### Fire

1. GenServer receives `{:fire_timer, session_id, token}`
2. Validates token
3. Calls `AgentManager.send_message(session_id, message)`
4. Clears or reschedules based on mode
5. Broadcasts `timer_updated` event

### Cancel

1. User picks "Cancel Scheduled Message"
2. LiveView sends `cancel_timer` event
3. Backend calls `OrchestratorTimers.cancel(session_id)`
4. Server cancels timer ref, removes state
5. Broadcasts `timer_updated` with `nil`
6. LiveView clears timer display

---

## Application Wiring

Add `OrchestratorTimers.Server` to the supervision tree in `application.ex`. Insert it **after `EyeInTheSky.RateLimiter` and before `EyeInTheSkyWeb.Endpoint`**:

```elixir
EyeInTheSky.RateLimiter,
EyeInTheSky.OrchestratorTimers.Server,  # <-- here
EyeInTheSkyWeb.Endpoint
```

The supervisor uses `strategy: :rest_for_one`. Any process listed above `OrchestratorTimers.Server` in the children list (Repo, PubSub, AgentSupervisor, etc.) will restart the timer server if it crashes, wiping all in-memory timer state. This is acceptable given the "does not survive restart" constraint and is expected behavior.

---

## Logging

Log at each lifecycle point with `session_id`, `mode`, `next_fire_at`:

- Timer scheduled (new)
- Timer replaced
- Timer cancelled
- Timer fired
- Delivery succeeded
- Delivery failed (with reason)

---

## Testing Plan

### Unit tests — `OrchestratorTimers.Server`

- `schedule_once` creates state
- `schedule_repeating` creates state
- Scheduling replaces existing timer (returns `:replaced`)
- `cancel` removes state
- Stale token fire is ignored
- One-shot removes itself after fire
- Repeating reschedules after fire
- Delivery failure: one-shot removes, repeating reschedules

### LiveView tests — `DmLive`

- Hamburger menu renders with all five items (Reload, Export, Notify, Schedule Message, Cancel Scheduled Message)
- "Cancel Scheduled Message" only shown when `@active_timer` is not nil
- Scheduling updates timer display
- Cancelling removes timer display
- Active timer shown after remount (via `get_timer` on mount)

### Manual integration

1. Open DM page for an orchestrator session
2. Schedule one-shot for 1 minute
3. Navigate away
4. Wait — confirm message delivered to session
5. Repeat with repeating mode
6. Cancel repeating — confirm no further messages fire

---

## Non-Goals (this iteration)

- Restart persistence / DB storage
- Cron expressions
- Custom message editing
- Multiple concurrent timers per session
- Oban integration
- AgentWorker coupling

## Future Upgrade Path

If restart persistence is needed later:
- Add `nudge_timers` DB table with `session_id`, `message`, `fire_at`, `interval_ms`
- Add a lightweight polling worker (like the existing `JobEnqueuer`)
- Keep the `OrchestratorTimers` public API unchanged

The DM page and calling code require no rewrite.

---

## Naming

UI: "Schedule Message" / "Reminder" / "Auto-nudge"

Code: `OrchestratorTimers` / `OrchestratorTimers.Server`

Avoid naming the module just `Timer` — it tells you nothing about what it's managing.
