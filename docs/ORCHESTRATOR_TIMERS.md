# OrchestratorTimers

Session-scoped timeout timers that outlive the DM LiveView socket. When a timer fires, it sends a predefined message to the session via `AgentManager.send_message/3`. Useful for auto-nudging orchestrator agents to check in with their team.

Timers are in-memory only; they do not survive application restarts.

## Architecture

### Modules

| Module | Role |
|--------|------|
| `EyeInTheSky.OrchestratorTimers` | Public API; all callers use this |
| `EyeInTheSky.OrchestratorTimers.Server` | GenServer; owns state, fires timers, delivers messages |
| `EyeInTheSky.OrchestratorTimers.Timer` | Struct for an active timer record |
| `EyeInTheSkyWeb.DmLive.TimerHandlers` | LiveView event handlers for schedule/cancel |
| `EyeInTheSkyWeb.DmLive.MountState` | Subscribes to timer PubSub on mount, assigns `@active_timer` |

### Supervision

`OrchestratorTimers.Server` runs under the application supervisor in `application.ex`, placed after `RateLimiter` and before `Endpoint`:

```elixir
EyeInTheSky.RateLimiter,
EyeInTheSky.OrchestratorTimers.Server,
EyeInTheSkyWeb.Endpoint
```

The supervisor uses `strategy: :rest_for_one`, so a crash of any upstream child (Repo, PubSub, etc.) restarts the timer server and wipes all in-memory state. This is expected.

### Why a separate GenServer

- Timers must outlive the LiveView socket (user navigating away must not cancel the timer)
- Timer lifecycle is independent of `AgentWorker` run lifecycle
- A single registry GenServer is simple and easy to query

## State Model

One map entry per session with an active timer. State is the GenServer's internal map:

```elixir
%{
  session_id => %Timer{
    token: reference(),        # stale-message guard (make_ref/0)
    timer_ref: reference(),    # Process.send_after ref
    mode: :once | :repeating,
    interval_ms: integer(),
    message: String.t(),
    started_at: DateTime.t(),
    next_fire_at: DateTime.t()
  }
}
```

## Public API

All functions are in `EyeInTheSky.OrchestratorTimers`:

```elixir
# Schedule a one-shot timer. Replaces any existing timer for the session.
OrchestratorTimers.schedule_once(session_id, delay_ms, message \\ default_message())
# => {:ok, :scheduled} | {:ok, :replaced}

# Schedule a repeating timer. Replaces any existing timer for the session.
OrchestratorTimers.schedule_repeating(session_id, interval_ms, message \\ default_message())
# => {:ok, :scheduled} | {:ok, :replaced}

# Cancel the active timer. No-op if none active.
OrchestratorTimers.cancel(session_id)
# => {:ok, :cancelled} | {:ok, :noop}

# Return the active Timer struct, or nil.
OrchestratorTimers.get_timer(session_id)
# => %Timer{} | nil

# Return all active Timer structs.
OrchestratorTimers.list_active()
# => [%Timer{}]

# The default message sent when a timer fires.
OrchestratorTimers.default_message()
# => "Please check in with your team members and report their current status and any blockers."
```

## Timer Semantics

### One-shot

1. `schedule_once/3` stores the timer and starts a `Process.send_after`
2. On fire: delivers message via `AgentManager.send_message/3`, removes timer from state

### Repeating

1. `schedule_repeating/3` stores the timer and starts a `Process.send_after`
2. On fire: delivers message, reschedules with a new `next_fire_at`, keeps running until cancelled or replaced

### Replace-on-reschedule

Scheduling a new timer when one is already active cancels the old one and replaces it. Returns `{:ok, :replaced}`.

### Token correlation (stale message safety)

`Process.cancel_timer/1` does not guarantee the old timeout message is not already in the mailbox. Each timer carries a unique token (`make_ref/0`). When a `{:fire_timer, session_id, token}` message arrives, the server verifies the stored token matches. Mismatches (stale messages from replaced/cancelled timers) are silently dropped.

## Delivery

When a timer fires:

1. Token is validated against current state
2. `AgentManager.send_message(session_id, message, [])` is called
3. On success: one-shot removes itself; repeating reschedules
4. On failure: one-shot still removes itself; repeating still reschedules (logs the failure). No backoff on repeating delivery failure; scheduling and delivery are separate concerns.

## PubSub Events

All events go through `EyeInTheSky.Events`. Never call `Phoenix.PubSub` directly.

**Topic:** `"session:<session_id>:timer"`

### Subscribe

```elixir
Events.subscribe_session_timer(session_id)
```

Called in `DmLive.MountState.setup_subscriptions/1` on LiveView mount.

### Broadcasts

| Function | Payload | When |
|----------|---------|------|
| `Events.timer_scheduled(session_id, timer)` | `{:timer_scheduled, %Timer{}}` | Timer created or replaced |
| `Events.timer_cancelled(session_id)` | `:timer_cancelled` | Timer explicitly cancelled |
| `Events.timer_fired(session_id, timer_or_nil)` | `{:timer_fired, %Timer{} \| nil}` | Timer fired; `nil` for one-shot (removed), `%Timer{}` for repeating (rescheduled) |

### DmLive handle_info

```elixir
def handle_info({:timer_scheduled, timer}, socket)   # assigns @active_timer = timer
def handle_info(:timer_cancelled, socket)             # assigns @active_timer = nil
def handle_info({:timer_fired, timer_or_nil}, socket) # assigns @active_timer = timer_or_nil
```

## UI Integration

### Hamburger menu

The DM page uses a unified hamburger/kebab menu (desktop and mobile) in `dm_page.ex`. Menu items include:

- Reload
- Export
- Notify
- **Schedule Message** (opens the schedule modal)
- **Cancel Schedule** (only shown when `@active_timer` is not nil; styled as error/destructive)

### Schedule modal

Triggered by `phx-click="open_schedule_timer"`. Sets `@active_overlay` to `:schedule_timer`.

Fields:
- **Mode:** One-shot or Repeating (separate preset button groups)
- **Duration presets:** 5m, 10m, 15m, 30m, 1h
- **Message:** Uses `default_message()` (no custom message editor)

Clicking a preset button fires `phx-click="schedule_timer"` with `phx-value-mode` and `phx-value-preset`.

Preset values are resolved in `TimerHandlers`:

```elixir
@presets_ms %{
  "5m"  => 5 * 60 * 1_000,
  "10m" => 10 * 60 * 1_000,
  "15m" => 15 * 60 * 1_000,
  "30m" => 30 * 60 * 1_000,
  "1h"  => 60 * 60 * 1_000
}
```

### Active timer badge

When `@active_timer` is not nil, the DM header shows a badge with the mode ("Once" or "Repeating") and a clock icon. Visible on desktop (hidden on mobile via `hidden sm:flex`).

### Mount

On mount, `MountState.assign_defaults/2` calls `OrchestratorTimers.get_timer(session.id)` to restore the `@active_timer` assign. This means navigating away and back preserves the timer display.

## Resumable Session Support

Timers are independent of session status. A timer scheduled on a "waiting" (headless/resumable) session will fire and call `AgentManager.send_message/3` regardless of whether the user is viewing the DM page. If the session's AgentWorker is not running, delivery fails but the timer lifecycle continues (repeating timers keep rescheduling).

## Event Flow Summary

### Schedule

1. User opens hamburger menu, clicks "Schedule Message"
2. Modal opens with preset buttons
3. User clicks a preset (e.g., "15m" one-shot)
4. `handle_event("schedule_timer", ...)` calls `OrchestratorTimers.schedule_once/3`
5. Server stores timer, broadcasts `Events.timer_scheduled/2`
6. DmLive `handle_info` updates `@active_timer`

### Fire

1. Server receives `{:fire_timer, session_id, token}`
2. Validates token
3. Calls `AgentManager.send_message/3`
4. One-shot: removes timer, broadcasts `{:timer_fired, nil}`
5. Repeating: reschedules, broadcasts `{:timer_fired, new_timer}`

### Cancel

1. User clicks "Cancel Schedule" in hamburger menu
2. `handle_event("cancel_timer", ...)` calls `OrchestratorTimers.cancel/1`
3. Server cancels timer ref, removes state, broadcasts `:timer_cancelled`
4. DmLive `handle_info` clears `@active_timer`

## Testing

Tests in `test/eye_in_the_sky/orchestrator_timers_test.exs` cover:

- `schedule_once` and `schedule_repeating` create correct state
- Replace-on-reschedule returns `:replaced`
- Cancel removes state; no-op when nothing active
- Stale token messages are ignored
- One-shot removes itself after firing
- Repeating reschedules after firing
- Delivery failure: one-shot still removes, repeating still reschedules

## Key Files

| File | Purpose |
|------|---------|
| `lib/eye_in_the_sky/orchestrator_timers.ex` | Public API |
| `lib/eye_in_the_sky/orchestrator_timers/server.ex` | GenServer implementation |
| `lib/eye_in_the_sky/orchestrator_timers/timer.ex` | Timer struct |
| `lib/eye_in_the_sky/events.ex` | PubSub helpers (lines 65, 305-314) |
| `lib/eye_in_the_sky/application.ex` | Supervision tree registration |
| `lib/eye_in_the_sky_web/live/dm_live.ex` | handle_event + handle_info for timers |
| `lib/eye_in_the_sky_web/live/dm_live/timer_handlers.ex` | Schedule/cancel event handlers |
| `lib/eye_in_the_sky_web/live/dm_live/mount_state.ex` | PubSub subscription + initial assign |
| `lib/eye_in_the_sky_web/components/dm_page.ex` | Hamburger menu + schedule modal + timer badge |
| `test/eye_in_the_sky/orchestrator_timers_test.exs` | Unit tests |
| `docs/superpowers/specs/2026-04-06-orchestrator-timer-design.md` | Original design spec |

## Non-Goals (current iteration)

- Restart persistence / DB storage
- Cron expressions
- Custom message editing
- Multiple concurrent timers per session
- Oban integration

## Future Upgrade Path

If restart persistence is needed: add a `nudge_timers` DB table, a lightweight polling worker, and keep the `OrchestratorTimers` public API unchanged. No LiveView or calling code changes required.
