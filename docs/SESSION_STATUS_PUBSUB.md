# Session Status PubSub Contract

How session status changes propagate from the scheduler to the UI (rail sidebar and DM page), and what can go wrong.

---

## Status values

| Value | Meaning |
|-------|---------|
| `"working"` | Claude process is actively running |
| `"idle"` | Process finished cleanly (Stop hook fired) |
| `"waiting"` | Headless/sdk-cli session ended; can be resumed |
| `"completed"` | Session explicitly closed |
| `"failed"` | Process crashed or zombie-swept |
| `"archived"` | Auto-archived after 30 min idle with no active tasks |

---

## PubSub topics and which UI surfaces subscribe

| Topic | Payload | Rail sidebar | DM page |
|-------|---------|:---:|:---:|
| `"agents"` | `{:agent_updated, session}` | ✓ | ✓ |
| `"agents"` | `{:agent_stopped, session}` | ✓ | ✓ |
| `"agent:working"` | `{:agent_working, session}` | — | ✓ |
| `"agent:working"` | `{:agent_stopped, session}` | — | ✓ |
| `"session:<id>:status"` | `{:session_status, id, status}` | — | — |

`Events.session_status/2` broadcasts to `"session:<id>:status"` — a topic **neither the rail nor DM page subscribes to**. It is only consumed by session-scoped views (e.g. session detail panel). Do not use it to update aggregate list UIs.

---

## Normal status transition path

Driven by Claude Code hooks calling the REST API:

```
UserPromptSubmit hook  →  PATCH /api/v1/sessions/:uuid  status="working"
                          Events.agent_working(session)

Stop hook              →  PATCH /api/v1/sessions/:uuid  status="idle"
                          Events.session_updated(session)
                          Events.agent_stopped(session)

SessionEnd hook (sdk)  →  PATCH /api/v1/sessions/:uuid  status="waiting"
SessionEnd hook (cli)  →  PATCH /api/v1/sessions/:uuid  status="completed"
```

Both broadcast to the `"agents"` topic so the rail and DM page update immediately.

---

## Zombie sweep (`AgentStatus` scheduler)

Runs every 5 minutes. Finds sessions stuck in `"working"` with no heartbeat for >30 minutes — these are processes that died without firing the Stop hook (kill -9, OOM, crash).

**File:** `lib/eye_in_the_sky/scheduler/agent_status.ex` — `sweep_zombie_sessions/0`

The sweep:
1. Bulk-updates `sessions.status = "failed"` via `Repo.update_all`
2. Iterates zombie structs and broadcasts on `"agents"`:
   - `Events.session_updated(updated)` → `{:agent_updated, session}` — rail picks this up
   - `Events.session_failed(updated, "zombie_swept")` → `{:agent_stopped, session}` — DM page picks this up
3. Bulk-updates linked `agents.status = "failed"`

### Bug that was fixed (2026-07-09)

The sweep previously called only `Events.session_status(s.id, "failed")`, which broadcasts to `"session:<id>:status"`. Neither the rail nor DM page subscribes to that topic, so the green dot persisted forever on crashed sessions.

Fix: replace with `Events.session_updated` + `Events.session_failed` which both hit the `"agents"` topic.

---

## Dead idle archive (`AgentStatus` scheduler)

Also runs every 5 minutes. Archives sessions that are `"idle"` for >30 minutes with no active tasks.

**File:** `lib/eye_in_the_sky/scheduler/agent_status.ex` — `archive_dead_idle_sessions/0`

After archiving, broadcasts `Events.session_updated(updated)` on the `"agents"` topic so the rail removes the entry from the active list.

## Idle ticket nudges (`IdleTicketNudger` scheduler)

Also runs every 5 minutes. It finds unarchived sessions in `idle` status that
are older than the nudge cutoff and still have open linked tasks. Instead of
changing session status, it sends a DM asking the session to update the ticket
status or notes if applicable.

**File:** `lib/eye_in_the_sky/scheduler/idle_ticket_nudger.ex`

Delivery uses `DMDelivery.deliver_or_persist/4`, so terminal-owned sessions get
a durable inbox record and the Phoenix app does not start an `AgentWorker` for
them. The worker uses cooldown and recent-message dedupe; it is a reminder path,
not a lifecycle cleanup path.

## Terminal-owned sessions

Terminal-launched Codex sessions are recorded with `entrypoint="cli"` and
`managed_by_app=false`. They are process-external from the Phoenix app's
perspective: incoming messages may be logged to the inbox, but the app must not
start or resume an `AgentWorker` for them.

`AgentStatus` filters terminal-owned sessions out of dead-idle archive and
zombie sweep candidates. `IdleTicketNudger` still includes terminal-owned idle
sessions with open tasks, but delivery persists the DM only and does not start
an app worker.

The Codex Stop hook can mark a terminal session `idle` between turns, and that
does not mean there is a dead app-owned worker to reclaim. If a terminal session
later appears as `status="working"` with `archived_at` still set, it was revived
without being unarchived. Clear `archived_at` with `eits sessions unarchive
<uuid>` or by the resume path before treating it as an active visible session.

---

## Adding a new UI surface that shows session status

If you add a LiveView that displays session status:

1. Subscribe to `"agents"` in `mount/3` (guard with `connected?/1`):
   ```elixir
   if connected?(socket), do: Events.subscribe_agents()
   ```

2. Handle both update and stop events:
   ```elixir
   def handle_info({:agent_updated, session}, socket), do: ...
   def handle_info({:agent_stopped, session}, socket), do: ...
   ```

3. Do **not** rely on `"session:<id>:status"` for list-level UI — that topic is only for session-detail views that already know which session to watch.

---

## Green dot logic

The green active indicator maps to session status as follows:

| Status | Shows green dot |
|--------|:-:|
| `"working"` | ✓ |
| `"idle"` | — |
| `"waiting"` | — |
| `"completed"` | — |
| `"failed"` | — |
| `"archived"` | — |

See `<.status_dot>` in `lib/eye_in_the_sky_web/components/core_components.ex` for the component implementation.
