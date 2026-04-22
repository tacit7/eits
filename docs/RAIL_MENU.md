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
assets/js/hooks/rail_state.js                               # localStorage persistence for project selection
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

Chat and Canvas lock the flyout open. Clicking their icon again does not collapse. Closing while on a sticky page restores that section. All other sections collapse on click.

```elixir
@sticky_sections [:chat, :canvas]
defp sticky_section?(section), do: section in @sticky_sections
```

Use `sticky_section?/1` everywhere. Do not hardcode `[:chat, :canvas]` inline elsewhere. This centralized attr makes future changes (e.g., adding `:notes` as sticky) trivial.

---

## Flyout Sections

### Sessions Flyout

**Lazy loader**: `load_flyout_sessions/3`

**UI features**:
- **Filter bar**: name input (300ms debounce) filters sessions server-side; sort popup (Last activity, Created, Name); sort icon highlights when non-default
- **Flat list**: sessions displayed without active/stopped grouping; status indicated by status dot (color-coded)
- **New agent form**: inline form to create a new session; fires `new_session` directly when project is selected via dropdown
- **Nav links**: All Sessions, List view links at top

**State preservation**: filter state (sort, name) preserved across project switches and flyout toggles via `session_filter` and `session_sort` assigns.

**Project scope**: if `sidebar_project` is set, only shows sessions for that project. Otherwise shows all sessions globally.

---

### Tasks Flyout

**Lazy loader**: `maybe_load_tasks/3`

**UI features**:
- **Nav links**: All, List, Kanban at top (direct links to /tasks, /tasks?view=list, /tasks?view=kanban)
- **State filter**: popup with workflow states (To Do, In Progress, In Review, Done, Archived); filters tasks by selected state; Archived excluded by default
- **Live search**: text input filters task names in real-time across visible list
- **Explicit empty states**: "No tasks yet" when list is empty
- **Kanban hint**: if Kanban view is available, "Try Kanban" hint shown

**State preservation**: search and filter state preserved; last 50 tasks loaded per project.

**Project scope**: tasks are always project-scoped. If no project selected, shows empty state.

**Archived handling**: archived tasks excluded from query by default; state filter allows user to view them. Rail does not filter after the fact — all filtering happens in the context query.

---

### Teams Flyout

**Lazy loader**: `maybe_load_teams/3`

**UI features**:
- Lists teams for the current project with member count (e.g. "Team Name (3 members)")
- Direct links to team pages

**Project scope**: if `sidebar_project` is set, shows only teams in that project. Otherwise empty state.

---

### Canvas Flyout

**Lazy loader**: `maybe_load_canvases/2`

**UI features**:
- Lists each canvas with its sessions
- Each session shows status dot + name, linking to that session's DM
- Sessions listed under each canvas with live status indicators (color-coded dot)
- Provider icon (pulsing and raised opacity when session is working) — click focuses the floating chat window for that session
- Session name — click focuses the floating chat window
- Session logo — click navigates to the session's DM page

**Nav behavior**:
- On non-canvas pages: canvas rail icon navigates to /canvases directly
- On canvas pages: canvas rail icon opens the flyout (no collapse on click due to sticky section)

**Cross-canvas focus**: Clicking a session name navigates to `/canvases/:id?focus=:session_id`. Canvas page reads the focus param in `handle_params` and dispatches `canvas:focus-session` after all windows are in DOM.

---

### Chat Flyout

**Lazy loader**: `maybe_load_channels/3`

**UI features**:
- Lists channels for current project (or global channels if no project selected)
- Direct navigation to channel pages

**Nav behavior**: Chat rail icon opens-only (no collapse on click due to sticky section).

---

### Usage Section

No lazy loader — section just displays a link to `/usage` ("Usage Dashboard").

---

### Jobs Section

**Lazy loader**: `maybe_load_jobs/2` (loads up to 15 jobs)

**UI features**:
- Each job shows: enabled/disabled dot + name + schedule value list
- Nav links: "All Jobs", optional "Project Jobs" link (if project selected)
- "No jobs" empty state when none exist

**Project scope**: if `sidebar_project` is set, shows project-specific job nav link.

---

## Lazy Loaders

Data is only fetched when entering a section, not on every page render:

| Section     | Loader                    | Project-scoped |
|-------------|---------------------------|----------------|
| `:sessions` | `load_flyout_sessions/3`  | Yes            |
| `:tasks`    | `maybe_load_tasks/3`      | Yes            |
| `:chat`     | `maybe_load_channels/3`   | Yes            |
| `:teams`    | `maybe_load_teams/3`      | Yes            |
| `:canvas`   | `maybe_load_canvases/2`   | No             |
| `:jobs`     | `maybe_load_jobs/2`       | Yes            |
| `:usage`    | —                         | —              |

Sessions are also re-fetched when `sidebar_project` changes (project switch triggers a reload).

---

## Project Context

### How `sidebar_project` is set

Project-scoped pages (`/projects/:id/*`) set `sidebar_project` to the project struct in `mount/3`. Global pages (`/usage`, `/jobs`, `/tasks`, `/canvases`, etc.) set it to `nil`.

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

`update/2` contains a nil-guard to prevent parent re-renders from clearing the locally selected project within a single LiveView process:

```elixir
sidebar_project =
  case assigns do
    %{sidebar_project: p} when not is_nil(p) -> p
    _ -> socket.assigns[:sidebar_project]
  end
```

**This guard works within the same LiveView process** (push_patch navigations). Cross-LiveView navigation would normally reset `sidebar_project` to nil because `mount/3` re-runs and reinitializes to nil before `update/2` fires.

### Project Persistence Across Cross-LiveView Navigation (Fixed)

**Previously**: Cross-LiveView navigation lost project selection. When navigating from a project-scoped page (`/projects/:id/*`) to a global page (`/usage`, `/jobs`, `/tasks`), the rail would remount, reset `sidebar_project: nil`, and the nil-guard fallback would also be nil. Project was gone.

**Now fixed** via localStorage + RailState hook:

**rail_state.js**:
- On hook `mounted()`, reads `rail_project_id` from localStorage
- Pushes `restore_project` event to LiveComponent with the saved project_id
- On `save_project` event from server, writes/clears `rail_project_id` in localStorage

**rail.ex**:
- `handle_event("restore_project")`: if `sidebar_project` is nil (global page), loads the project by ID and assigns it
- If the project no longer exists, pushes `save_project` with nil to clear stale localStorage entry
- `handle_event("select_project")`: after setting project locally, pushes `save_project` with new project_id (or nil if toggled off) so localStorage stays in sync

**Guard**: restore only runs when `sidebar_project` is nil. Project-scoped pages set a non-nil project first (via `update/2`), so the restore is a no-op on those pages — route-derived project is never overridden.

Result: Project selection now persists across all page navigations.

---

## State Ownership Rules

```
Rail owns:      UI interaction state — active_section, flyout_open, filter/search state,
                sidebar_project fallback (via localStorage)
Parents own:    Route-derived context — sidebar_tab, sidebar_project (for project-scoped routes)
URL params own: Cross-route persistence when needed (e.g., ?focus= for canvas)
Contexts own:   Data retrieval, authorization, filtering, persistence
```

The rail must not become a source of truth for project authorization or durable project selection beyond the localStorage fallback. It displays context; it does not decide access.

---

## Known Gotchas

1. **`transition-all` flicker** — do not put `transition-all` inside stream items. CSS transitions replay from initial state (e.g. opacity-0) on stream reinsert, causing visible flicker.

2. **`phx-update="ignore"` on dropdowns** — use with a stable `id` on the dropdown root. morphdom only syncs `data-*` attributes on ignored elements; `open` and other attributes are preserved.

3. **DM Live sidebar_tab** — `DmLive` sets `sidebar_tab: :sessions`. Navigating to a DM does not change the active section.

4. **Archived task leakage** — tasks context must filter archived tasks at query time; the rail does not filter them after the fact.

5. **nil project_id Ecto warning** — some queries emit a warning when `project_id: nil` is passed. Always guard: `if project, do: Keyword.put(opts, :project_id, project.id), else: opts`.

6. **Canvas routes in :app live_session** — canvas pages mount inside the same `:app` live session, so the rail persists across canvas navigation. Canvas URLs do not carry `?project_id=X`; project context is not recovered from URL on canvas pages. Project selection is preserved via localStorage fallback.

7. **`sidebar_project: nil` does not clear the rail's project (within same LV process)** — the nil-guard in `update/2` preserves the locally held project within a LiveView process. Across LiveView navigation, persistence is now handled by localStorage (see Project Persistence section above).

8. **Rail LiveComponent state is not route-durable** — LiveComponent state only survives within the current parent LiveView process. Cross-route persistence is handled via URL params (canvas focus), localStorage (project selection), or maintained in contexts.

9. **`phx-change` on bare inputs is unreliable** — bare inputs (no form wrapper) only fire `phx-change` on blur. Use `phx-keyup` + `phx-debounce="300"` for real-time filtering. Applied to: session name filter, task search input.

10. **Filter state preservation across toggles** — when user toggles the flyout closed and opens it again, filter/search state is preserved. This is intentional for UX but means clearing a search is a deliberate user action, not a side effect of navigation.
