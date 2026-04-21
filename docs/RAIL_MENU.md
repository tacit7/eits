# Rail Menu

The rail is a persistent LiveComponent (`EyeInTheSkyWeb.Components.Rail`) mounted in `app.html.heex`. It is shared across all pages in the `:app` live session and provides navigation, flyout panels, and project context.

## Files

```
lib/eye_in_the_sky_web/components/rail.ex                   # Main LiveComponent — state machine, event handlers, lazy loaders
lib/eye_in_the_sky_web/components/rail/flyout.ex            # Flyout panel rendering (all sections)
lib/eye_in_the_sky_web/components/rail/project_switcher.ex  # Project picker overlay
lib/eye_in_the_sky_web/components/rail/project_actions.ex   # Project CRUD + select event handlers
lib/eye_in_the_sky_web/components/rail/helpers.ex           # Small utilities (project_initial, etc.)
lib/eye_in_the_sky_web/components/layouts/app.html.heex     # Layout — mounts the rail with sidebar_tab + sidebar_project
```

---

## Section Map

The rail maps `sidebar_tab` atoms (set by each LiveView) to `active_section` atoms (which flyout to show):

```elixir
@section_map %{
  sessions:      :sessions,
  overview:      :sessions,
  tasks:         :tasks,
  kanban:        :tasks,
  prompts:       :prompts,
  chat:          :chat,
  notes:         :notes,
  skills:        :skills,
  teams:         :teams,
  canvas:        :canvas,
  canvases:      :canvas,
  notifications: :notifications,
  usage:         :usage,
  jobs:          :jobs,
  config:        :sessions,
  settings:      :sessions,
  agents:        :sessions,
  files:         :sessions,
  bookmarks:     :sessions
}
```

`@valid_sections` is the list of atoms that `parse_section/1` accepts from `toggle_section` click events. Any section not in this list falls back to `:sessions`.

---

## Sticky Sections

Chat and Canvas lock the flyout open. Clicking their icon again does not collapse. Closing while on a sticky page restores that section.

```elixir
@sticky_sections [:chat, :canvas]
defp sticky_section?(section), do: section in @sticky_sections
```

Use `sticky_section?/1` everywhere. Do not hardcode `[:chat, :canvas]` inline elsewhere.

---

## Lazy Loaders

Data is only fetched when entering a section, not on every page render:

| Section     | Loader                    |
|-------------|---------------------------|
| `:sessions` | `load_flyout_sessions/3`  |
| `:tasks`    | `maybe_load_tasks/3`      |
| `:chat`     | `maybe_load_channels/3`   |
| `:teams`    | `maybe_load_teams/3`      |
| `:canvas`   | `maybe_load_canvases/2`   |
| `:jobs`     | `maybe_load_jobs/2`       |

Sessions are also re-fetched when `sidebar_project` changes (project switch triggers a reload).

---

## Project Context

### How `sidebar_project` is set

Project-scoped pages (`/projects/:id/*`) set `sidebar_project` to the project struct in `mount/3`. Global pages (`/usage`, `/jobs`, `/tasks`, etc.) historically set it to `nil`.

The layout passes it directly to the rail:

```heex
<.live_component
  module={EyeInTheSkyWeb.Components.Rail}
  id="app-rail"
  sidebar_tab={assigns[:sidebar_tab] || :sessions}
  sidebar_project={assigns[:sidebar_project]}
  ...
/>
```

### The Nil-Guard

`update/2` contains a nil-guard to prevent parent re-renders from clearing the locally selected project:

```elixir
sidebar_project =
  case assigns do
    %{sidebar_project: p} when not is_nil(p) -> p
    _ -> socket.assigns[:sidebar_project]
  end
```

**This guard works within the same LiveView process** (push_patch navigations). It does NOT survive cross-LiveView navigation because `mount/3` re-runs and resets `sidebar_project: nil` before `update/2` fires. When `update/2` then receives `nil` from the global page, the fallback is also `nil`.

### Project Switch

User clicks a project in the project picker → `handle_event("select_project")` → `ProjectActions.handle_select_project/2`. This sets `sidebar_project` only in the rail's local assigns. It does not navigate, broadcast, or persist anywhere. Clicking the same project again toggles it off (sets to nil).

---

## Known Issue: Project Lost on Cross-LiveView Navigation

**Symptom**: User selects Project 1, navigates to a global page (`/usage`, `/jobs`, `/tasks`), project is lost. All subsequent flyout content (sessions, tasks, teams) shows global unscoped results.

**Root cause**: Cross-LiveView navigation remounts the LiveComponent. `mount/3` initializes `sidebar_project: nil`. `update/2` receives `nil` from the global page — nil-guard falls back to the mount default (also `nil`). Project is gone.

**Why global pages set `sidebar_project: nil`**: No good reason. The convention signals "no project scope" but the nil-guard was added to make that safe. The real problem is the remount resets state before the nil-guard can protect it.

**Fix (not yet implemented)**:

Two parts:

1. **Persist last-selected project_id via localStorage** using the existing `RailState` JS hook:
   - On project select, write `last_project_id` to localStorage
   - On hook `mounted`, push `last_project_id` back to the LiveComponent via `pushEvent("restore_project", %{project_id: id})`
   - Rail handles `restore_project` event: if `sidebar_project` is nil, load and assign the project

2. **Stop setting `sidebar_project: nil` on global pages** — it is redundant given the nil-guard and actively confusing.

Until this is fixed, the project selection does not survive navigating away from a project-scoped page.

---

## State Ownership Rules

```
Rail owns:      UI interaction state — active_section, flyout_open, filter/search state,
                locally selected sidebar_project fallback
Parents own:    Route-derived context — sidebar_tab, sidebar_project (for project-scoped routes)
URL params own: Cross-route persistence when needed (currently only used for canvas)
Contexts own:   Data retrieval, authorization, filtering, persistence
```

The rail must not become a source of truth for project authorization or durable project selection. It displays context; it does not decide access.

---

## Known Gotchas

1. **`transition-all` flicker** — do not put `transition-all` inside stream items. CSS transitions replay from initial state (e.g. opacity-0) on stream reinsert, causing visible flicker.

2. **`phx-update="ignore"` on dropdowns** — use with a stable `id` on the dropdown root. morphdom only syncs `data-*` attributes on ignored elements; `open` and other attributes are preserved.

3. **DM Live sidebar_tab** — `DmLive` sets `sidebar_tab: :sessions`. Navigating to a DM does not change the active section.

4. **Archived task leakage** — tasks context must filter archived tasks at query time; the rail does not filter them after the fact.

5. **nil project_id Ecto warning** — some queries emit a warning when `project_id: nil` is passed. Always guard: `if project, do: Keyword.put(opts, :project_id, project.id), else: opts`.

6. **Canvas routes in :app live_session** — canvas pages mount inside the same `:app` live session, so the rail persists across canvas navigation. Canvas URLs do not carry `?project_id=X`; project context is not recovered from URL on canvas pages.

7. **`sidebar_project: nil` does not clear the rail's project (within same LV process)** — the nil-guard in `update/2` preserves the locally held project within a LiveView process. Across LiveView navigation it does not help. See the known issue above.

8. **Rail LiveComponent state is not route-durable** — LiveComponent state only survives within the current parent LiveView process. Cross-route persistence must be carried through URL params, localStorage, or another durable source.

9. **`phx-change` on bare inputs is unreliable** — bare inputs (no form wrapper) only fire `phx-change` on blur. Use `phx-keyup` + `phx-debounce="300"` for real-time filtering. Applied to: session name filter, task search input.
