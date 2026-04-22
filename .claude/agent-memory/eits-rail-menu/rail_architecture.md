---
name: Rail Menu Architecture
description: File locations, section map, state machine, lazy loading, project persistence (localStorage fix), icon order, and known gotchas for the EITS rail menu
type: project
---

## File Locations

- `lib/eye_in_the_sky_web/components/rail.ex` — main LiveComponent, all state + event handlers
- `lib/eye_in_the_sky_web/components/rail/flyout.ex` — HEEx rendering, all section content
- `lib/eye_in_the_sky_web/components/rail/helpers.ex` — `project_initial/1` and minor utils
- `lib/eye_in_the_sky_web/components/rail/project_switcher.ex` — project picker dropdown
- `lib/eye_in_the_sky_web/components/rail/project_actions.ex` — project CRUD + select event handlers
- `lib/eye_in_the_sky_web/components/layouts/app.html.heex` — renders `<.live_component module={Rail} id="app-rail" sidebar_project={assigns[:sidebar_project]} ...>`
- `assets/js/hooks/rail_state.js` — RailState hook: localStorage persistence, mobile swipe, section restore
- `docs/RAIL_MENU.md` — full architecture doc (canonical reference)

## Section Map (current)

```elixir
@section_map %{
  sessions: :sessions, overview: :sessions,
  tasks: :tasks, kanban: :tasks,
  prompts: :prompts,
  chat: :chat,
  notes: :notes,
  skills: :skills,
  teams: :teams,
  canvas: :canvas, canvases: :canvas,
  notifications: :notifications,
  usage: :usage,      # was :sessions before — fixed
  jobs: :jobs,        # was :sessions before — fixed
  config: :sessions, settings: :sessions, agents: :sessions,
  files: :sessions, bookmarks: :sessions
}
```

`@valid_sections` includes: sessions, tasks, prompts, chat, notes, skills, teams, canvas, notifications, usage, jobs.

## Icon Strip Order (current)

sessions → tasks → notes → skills → teams → jobs → chat → prompts → usage → canvas

## State Machine

Key assigns:
- `active_section` — atom (one of the valid sections above)
- `flyout_open` — bool
- `sidebar_project` — Project struct or nil
- `sidebar_tab` — atom from parent LiveView
- `flyout_jobs` — list of ScheduledJob structs (lazy-loaded on :jobs section)

## update/2 Nil-Guard Pattern (CRITICAL)

```elixir
sidebar_project =
  case assigns do
    %{sidebar_project: p} when not is_nil(p) -> p
    _ -> socket.assigns[:sidebar_project]
  end
```

Parent passing nil does NOT clear the Rail's project — it means "keep current". This guard works within the same LiveView process (push_patch). It does NOT survive cross-LiveView navigation because mount/3 resets to nil before update/2 fires. See project persistence below.

## Sticky Sections (Chat + Canvas)

```elixir
@sticky_sections [:chat, :canvas]
defp sticky_section?(section), do: section in @sticky_sections
```

Always use `sticky_section?/1`. Never hardcode `[:chat, :canvas]` inline.

## Lazy Loading Pattern

| Section | Loader |
|---------|--------|
| :sessions | `load_flyout_sessions/3` |
| :tasks | `maybe_load_tasks/3` |
| :chat | `maybe_load_channels/3` |
| :teams | `maybe_load_teams/3` |
| :canvas | `maybe_load_canvases/2` |
| :jobs | `maybe_load_jobs/2` (EyeInTheSky.ScheduledJobs.list_jobs()) |

Sessions also reload when `sidebar_project` changes.

## Project Persistence (localStorage fix — SHIPPED)

Cross-LiveView navigation remounts the LiveComponent. mount/3 resets sidebar_project to nil. The nil-guard in update/2 has no previous state to fall back to.

**Fix**: RailState hook + localStorage.

**JS side (`rail_state.js`)**:
- `mounted()` reads `rail_project_id` from localStorage, pushes `restore_project` event
- `handleEvent('save_project')` writes/clears `rail_project_id`

**Elixir side (`rail.ex`)**:
- `handle_event("restore_project")`: guard `when is_nil(socket.assigns.sidebar_project)` — only restores when parent hasn't set a project. Loads project by ID. On error (deleted project), pushes `save_project: nil` to clear stale entry.
- `handle_event("select_project")`: pushes `save_project` with project_id (or nil) after each selection so localStorage stays in sync.

Order is safe: `update/2` runs before hook `mounted()` fires, so project-scoped pages always win.

## Sessions Flyout

- Name filter: `phx-keyup` + `phx-debounce="300"` (bare input — phx-change only fires on blur)
- Sort options: `:created`, `:name` (last-activity removed from UI; `:last_activity` is still the default assign value but not shown)
- Sort indicator active condition: `@sort != :last_activity` (correct — default never shows as active)

## Tasks Flyout

- Search input: `phx-keyup` + `phx-debounce="300"` (same bare-input fix)
- Empty state: "No matching tasks" when search or state filter active; "No tasks" otherwise
- Kanban nav: always visible — live link when sidebar_project present, grayed-out span with tooltip when nil
- State filter popup: To Do (1) / In Progress (2) / In Review (4) / Done (3)

## Jobs Flyout

- Lazy-loaded on section activate via `maybe_load_jobs/2`
- Shows: enabled/disabled dot + name + schedule_value (cron expression)
- Nav: "All Jobs" → `/jobs`; "Project Jobs" → `/projects/:id/jobs` when sidebar_project set
- Empty state: "No jobs"

## Known Gotchas

1. `transition-all` inside stream items causes flicker on reinsert — don't use it
2. Dropdowns need `phx-update="ignore"` with stable `id` on root to survive morphdom
3. DM live sets `sidebar_tab: :sessions` — DM pages don't change the active section
4. `base_tasks_query` must filter `archived == false` by default (was leaking archived tasks)
5. Always guard `is_nil(project_id)` before building project-scoped Ecto queries — avoids nil comparison warning
6. Canvas routes are in `:app` live_session — they get the full rail layout
7. `sidebar_project: nil` from a parent does NOT clear the current rail project (within same LV process). For explicit clearing, introduce a sentinel like `:clear`
8. Rail LiveComponent state is NOT route-durable across LiveView navigation. Use localStorage (via RailState hook) for cross-route persistence — NOT URL params for the rail project.
9. `phx-change` on bare inputs (no form wrapper) only fires on blur. Use `phx-keyup` for real-time filtering.
10. Canvas URLs do NOT carry `?project_id=X`. There is no `maybe_assign_sidebar_project/2`. Project persistence is handled by the localStorage mechanism above.

## State Ownership Rules

- **Parent LiveViews** own route-derived context: `sidebar_tab` and project-scoped `sidebar_project`
- **Rail** owns UI interaction state: `active_section`, `flyout_open`, section filters/search, locally selected project fallback
- **localStorage** (via RailState hook) owns cross-route project persistence
- **Context modules** own data retrieval, authorization, filtering, and persistence
- Rail must not become the source of truth for project authorization
