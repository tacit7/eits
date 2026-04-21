---
name: Rail Menu Architecture
description: File locations, state machine, lazy loading, project persistence, and known gotchas for the EITS rail menu
type: project
---

## File Locations

- `lib/eye_in_the_sky_web/components/rail.ex` — main LiveComponent, all state + event handlers
- `lib/eye_in_the_sky_web/components/rail/flyout.ex` — HEEx rendering, all section content (sessions, tasks, canvas, chat, teams, notes, skills, notifications)
- `lib/eye_in_the_sky_web/components/rail/helpers.ex` — `project_initial/1` and minor utils
- `lib/eye_in_the_sky_web/components/rail/project_switcher.ex` — project picker dropdown component
- `lib/eye_in_the_sky_web/components/rail/project_actions.ex` — extracted handle_event handlers for project CRUD
- `lib/eye_in_the_sky_web/components/layouts/app.html.heex` — renders `<.live_component module={Rail} id="app-rail" sidebar_project={assigns[:sidebar_project]} ...>`

## State Machine

Rail is a LiveComponent. Key assigns:
- `active_section` — atom: `:sessions`, `:tasks`, `:canvas`, `:chat`, `:teams`, `:notes`, `:skills`, `:notifications`
- `flyout_open` — bool
- `sidebar_project` — Project struct or nil (drives Kanban link, project-scoped queries)
- `sidebar_tab` — atom from parent LiveView (`:tasks`, `:kanban`, `:sessions`, etc.)
- `@section_map` — maps sidebar_tab atoms → active_section atoms

## update/2 Nil-Guard Pattern (CRITICAL)

```elixir
sidebar_project =
  case assigns do
    %{sidebar_project: p} when not is_nil(p) -> p
    _ -> socket.assigns[:sidebar_project]
  end
```

Parent passing nil does NOT clear the Rail's project. This is intentional — prevents PubSub re-renders from wiping a locally-selected project. Every parent re-render calls update/2, so this guard matters.

## Sticky Sections (Chat + Canvas)

Canvas and chat pages lock the flyout open — can't collapse by clicking the icon again. If user clicks another section while sticky, close restores to the sticky section instead of collapsing.

```elixir
defp sticky_section(:canvas), do: :canvas
defp sticky_section(:canvases), do: :canvas
defp sticky_section(:chat), do: :chat
defp sticky_section(_), do: nil
```

`toggle_section` guard: `section not in [:chat, :canvas]` skips the collapse branch.

## Lazy Loading Pattern

Each section loads data only when navigating to it:
- `maybe_load_channels/3` — chat section
- `maybe_load_canvases/2` — canvas section
- `maybe_load_teams/3` — teams section
- `maybe_load_tasks/3` — tasks section (FTS via `Tasks.search_tasks` when search non-empty, `list_tasks_for_project` with project, global fallback)
- `load_flyout_sessions/3` — always loaded, reloads only when `sidebar_project` changes

## Project Persistence Across Navigation

LiveComponent re-mounts fresh on every parent LiveView change (different routes = different LV processes). To survive canvas → tasks navigation, canvas URLs carry `?project_id=X` when a project is active, and `CanvasLive.handle_params` reads it back via `maybe_assign_sidebar_project/2`.

## Sessions Flyout

Server-side filtering via `list_sessions_filtered/2` opts:
- `sort_by: :last_activity` (default) | `:created` | `:name`
- `name_filter: "string"` — prefix/contains match

## Tasks Flyout

- Last 50 tasks shown
- Search uses `Tasks.search_tasks/3` (PostgreSQL FTS) when non-empty
- State filter popup: To Do (1) / In Progress (2) / In Review (4) / Done (3)
- Nav links: All → `/tasks`, List → `/projects/:id/tasks` (needs sidebar_project), Kanban → `/projects/:id/kanban` (only renders when sidebar_project non-nil)

## Known Gotchas

1. `transition-all` inside stream items causes flicker on reinsert — don't use it
2. Dropdowns need `phx-update="ignore"` with stable `id` on the root to survive morphdom
3. `sidebar_tab` from `dm_live` was previously `:chat` — changed to `:sessions` so DM pages don't hijack the sessions flyout
4. `base_tasks_query` leaked archived tasks — now filters `archived == false` by default
5. Always branch on `is_nil(project_id)` before building project-scoped Ecto queries — avoids `comparing c.project_id with nil` warning
6. Canvas routes are in `:app` live_session (not a separate `:canvas` session) — they get the full rail layout
7. `sidebar_project: nil` from a parent does NOT clear the current rail project — it means "keep current". To explicitly clear in the future, introduce a sentinel like `:clear` or a separate `sidebar_project_action` assign. The current nil-guard in `update/2` is intentional.
8. Rail LiveComponent state is NOT route-durable. It only survives within the current parent LiveView process. Cross-route persistence must be carried through URL params (e.g. `?project_id=X`), parent assigns, or another durable source — not assumed to persist across route changes.

## How Parent Pages Set Sidebar Context

Project-scoped pages call `mount_project/3` from `ProjectLiveHelpers` — sets both `:sidebar_tab` and `:sidebar_project`. Non-project pages just set `:sidebar_tab`. Layout template uses `assigns[:sidebar_project]` (safe nil default).

## State Ownership Rules

- **Parent LiveViews** own route-derived context: `sidebar_tab` and project-scoped `sidebar_project`.
- **Rail** owns UI interaction state: `active_section`, `flyout_open`, section filters/search, and the locally selected project fallback (via nil-guard).
- **URL params** own cross-route persistence when navigating between LiveViews (e.g. `?project_id=X` on canvas URLs).
- **Context modules** own data retrieval, authorization, filtering, and persistence.
- Rail must not become the source of truth for project authorization or durable project selection.

Keep this boundary clear. When every feature adds one more special case to the rail, it becomes a hybrid of navigation manager, project selector, data loader, and route persistence layer — and starts to break.
