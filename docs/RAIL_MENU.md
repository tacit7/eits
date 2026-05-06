# Rail Menu

The rail is a persistent LiveComponent (`EyeInTheSkyWeb.Components.Rail`) mounted in `app.html.heex`. It is shared across all pages in the `:app` live session and provides navigation, flyout panels, and project context.

## Files

```
lib/eye_in_the_sky_web/components/rail.ex                     # Main LiveComponent — state machine, event handlers, lazy loaders
lib/eye_in_the_sky_web/components/rail/flyout.ex              # Flyout panel rendering (all sections)
lib/eye_in_the_sky_web/components/rail/project_switcher.ex    # Project picker overlay
lib/eye_in_the_sky_web/components/rail/project_actions.ex     # Project CRUD + select event handlers
lib/eye_in_the_sky_web/components/rail/file_actions.ex        # File event handlers (extracted from rail.ex)
lib/eye_in_the_sky_web/components/rail/filter_actions.ex      # Filter event handlers (search + pill filters for all sections)
lib/eye_in_the_sky_web/components/rail/loader.ex              # Data loaders for all flyout sections
lib/eye_in_the_sky_web/components/rail/helpers.ex             # Small utilities (project_initial, etc.)
lib/eye_in_the_sky_web/components/rail/flyout/*_section.ex     # Individual flyout sections (sessions, tasks, notes, agents, skills, prompts, teams, etc.)
lib/eye_in_the_sky_web/components/core_components.ex          # Core components, including custom_icon/1
lib/eye_in_the_sky_web/components/layouts/app.html.heex       # Layout — mounts the rail with sidebar_tab + sidebar_project
lib/eye_in_the_sky_web/live/shared/agents_helpers.ex          # AgentsHelpers.list_agents_for_flyout_filtered/3
lib/eye_in_the_sky_web/live/shared/skills_helpers.ex          # SkillsHelpers.list_skills_for_flyout_filtered/3
assets/js/hooks/rail_state.js                                 # localStorage persistence for project selection
assets/css/app.css                                            # --surface-sidebar token for rail + flyout theming
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
  agents:        :agents,
  files:         :files,
  bookmarks:     :sessions
}
```

`@valid_sections` is the list of atoms that `parse_section/1` accepts from `toggle_section` click events. Any section not in this list falls back to `:sessions`.

```elixir
@valid_sections ~w(sessions agents tasks prompts chat notes skills teams canvas notifications usage jobs files)
```

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

**Lazy loader**: `load_flyout_sessions/4`

**UI features**:
- **Flyout header icons**: globe icon links to `/sessions` (all sessions globally); list-bullet icon links to `/projects/:id/sessions` when a project is selected
- **Filter zone** (always visible):
  - **Search input**: debounced (300ms) name filter (server-side)
  - **Sort dropdown**: Last Activity / Created / Name; icon highlights when non-default
  - **Show toggle**: 20 / Active (limits results or filters to active-status only)
- **Flat list**: sessions displayed without active/stopped grouping; status indicated by status dot (color-coded)
- **New session button** (`+`): 
  - When project selected: fires `new_session` event directly with `project_id` (instant creation, no modal)
  - When no project: fires `toggle_new_session_form` (shows form with project picker)
- **Sticky footer nav links**: "All Sessions" (links to `/sessions`); "List" (links to `/projects/:id/sessions`, project-scoped; only shown when project selected)

**State preservation**: filter state (sort, name, show) preserved across project switches and flyout toggles via `session_filter`, `session_sort`, and `session_show` assigns.

**Project scope**: if `sidebar_project` is set, only shows sessions for that project. Otherwise shows all sessions globally.

---

### Tasks Flyout

**Lazy loader**: `load_flyout_tasks/3`

**UI features**:
- **Flyout header icons**: globe icon links to `/tasks` (all tasks globally); list-bullet icon links to `/projects/:id/tasks` when a project is selected
- **Filter zone** (always visible):
  - **Search input**: debounced filters task names in real-time
  - **State pills**: To Do / In Progress / In Review / Done (toggleable; clicking an active pill clears all filters)
- **Task list**: displays up to 50 tasks per project (archived excluded by default)
- **New task button** (`+`): opens inline modal with title + body fields
- **Explicit empty states**: "No tasks yet" when list is empty

**State preservation**: search and state filter preserved across toggles via `task_search` and `task_state_id` assigns.

**Project scope**: tasks are always project-scoped. If no project selected, shows empty state.

**Archived handling**: archived tasks excluded from query by default. State filter does not expose archived view in current UI.

---

### Notes Flyout

**Lazy loader**: `load_flyout_notes/3`

**UI features**:
- **Flyout header icons**: globe icon links to `/notes` (all notes globally); list-bullet icon links to `/projects/:id/notes` when a project is selected
- **Filter zone** (always visible):
  - **Search input**: filters note title/body in real-time
  - **Parent type pills**: Session / Task / Project (toggleable; clicking an active pill clears filters)
- **Note list**: displays notes with title + body preview (first 60 chars)
- **Note expansion**:
  - **Small notes** (< 200 bytes): render as `<details>` expand-in-place popups instead of navigating
  - **Large notes** (≥ 200 bytes): link navigates to edit page with "Edit →" affordance in expanded view
- **New note button** (`+`): navigates to `/notes/new` (creates a new note)
- **Empty state**: "No notes" when none exist

**State preservation**: search and parent_type filter preserved via `note_search` and `note_parent_type` assigns.

**Project scope**: if `sidebar_project` is set, loads only notes for that project. Otherwise loads all notes globally.

**Note structure**: each note has optional `title` and `body` fields. If title is empty, the first 60 chars of body is used as the label. If both are empty, shows "(empty)".

---

### Agents Flyout

**Lazy loader**: `load_flyout_agents_filtered/3`

**UI features**:
- **Flyout header icon**: hero-list-bullet icon links to `/projects/:id/agents` (project-scoped only)
- **Filter zone** (always visible):
  - **Search input**: filters agent name/description in real-time
  - **Scope pills**: All / Global / Project (toggleable)
    - **Global**: filters to `:agents` source (global agents)
    - **Project**: filters to `:project_agents` source (project-specific agents)
    - **All**: shows both sources
- **Agent list**: each row is clickable and opens the New Session form with that agent pre-filled in the agent selector
- **Prefill mechanism**: agent rows use `data-prefill-slug` and `data-prefill-label` attributes; `AgentCombobox` component reads these on mount to pre-select the agent
- **Empty state**: shown when no project selected

**State preservation**: search and scope filter preserved via `agent_search` and `agent_scope` assigns.

**Project scope**: agents are project-scoped. If no project selected, shows empty state.

---

### Skills Flyout

**Lazy loader**: `load_flyout_skills_filtered/3`

**UI features**:
- **Flyout header icon**: hero-bolt icon links to `/projects/:id/skills` (project-scoped only)
- **Filter zone** (always visible):
  - **Search input**: filters skill name/description in real-time
  - **Scope pills**: All / Global / Project (toggleable)
    - **Global**: filters to `:agents` source (global skills)
    - **Project**: filters to `:project_agents` source (project-specific skills)
    - **All**: shows both sources
- **Skill list**: expandable rows show description/snippet on click via `<details>` element
- **Skill icons**:
  - **Section header**: hero-bolt (for skills section)
  - **Command rows**: hero-slash (for slash commands)
  - **Skill rows**: hero-bolt (for skills; determined by source field)
- **Details preservation**: `phx-update="ignore"` on details element preserves open state across re-renders
- **Empty state**: shown when no project selected

**State preservation**: search and scope filter preserved via `skill_search` and `skill_scope` assigns.

**Project scope**: skills are project-scoped. If no project selected, shows empty state.

---

### Prompts Flyout

**Lazy loader**: `load_flyout_prompts/3`

**UI features**:
- **Flyout header icon**: hero-document-text icon links to `/projects/:id/prompts` (project-scoped)
- **Filter zone** (always visible):
  - **Search input**: filters prompt name/body in real-time
  - **Scope pills**: All / Global / Project (toggleable)
    - **Global**: filters to global prompts
    - **Project**: filters to project-specific prompts
    - **All**: shows both scopes
- **Prompt list**: displays prompt rows with title + body preview
- **New prompt button** (`+`): opens inline modal with title + body fields
- **Empty state**: "No prompts" when none exist

**State preservation**: search and scope filter preserved via `prompt_search` and `prompt_scope` assigns.

**Project scope**: if `sidebar_project` is set, loads project and global prompts. Otherwise loads only global prompts.

---

### Teams Flyout

**Lazy loader**: `load_flyout_teams_filtered/3`

**UI features**:
- **Flyout header icon**: hero-users icon links to `/teams` (global teams view)
- **Filter zone** (always visible):
  - **Search input**: filters team name in real-time
  - **Status pills**: Active / All / Archived (toggleable; clicking an active pill clears filters)
- **Team list**: displays teams with member count (e.g. "Team Name (3 members)")
- **Archived badge**: shown next to team name for archived teams
- **Empty state**: "No teams" when none exist; also shown when no project selected

**State preservation**: search and status filter preserved via `team_search` and `team_status` assigns.

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

### Files Flyout

**Lazy loader**: loads file tree on demand (no explicit loader function name, but data loads when section is opened)

**UI features**:
- **Flyout header icons**: refresh button (arrow-path icon) re-reads root nodes and re-fetches children for all currently expanded paths
- **Refresh behavior**: Preserves expanded state (does not clear); prunes any paths that no longer exist on disk (deleted between expand and refresh)
- **File tree**: hierarchical display with expand/collapse for directories
- **No broken state**: refresh handles deleted directories gracefully by filtering them from the expanded set

**Project scope**: files are project-scoped. If no project selected, shows empty state.

**Refresh implementation detail**: On refresh, for each expanded path, attempts to re-fetch children from disk. If a path fails to fetch (dir deleted or unreadable), it is removed from the expanded set but the rest of the tree is preserved.

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
- **Flyout header icons**: globe icon links to `/jobs` (all jobs globally); list-bullet icon links to `/projects/:id/jobs` when a project is selected
- Each job shows: enabled/disabled dot + name + schedule value list
- Nav links: "All Jobs", optional "Project Jobs" link (if project selected)
- "No jobs" empty state when none exist

**Project scope**: if `sidebar_project` is set, shows project-specific job nav link.

---

## Lazy Loaders

Data is only fetched when entering a section, not on every page render:

| Section     | Loader                          | Project-scoped |
|-------------|---------------------------------|----------------|
| `:sessions` | `load_flyout_sessions/4`        | Yes            |
| `:tasks`    | `load_flyout_tasks/3`           | Yes            |
| `:chat`     | `maybe_load_channels/3`         | Yes            |
| `:teams`    | `load_flyout_teams_filtered/3`  | Yes            |
| `:agents`   | `load_flyout_agents_filtered/3` | Yes            |
| `:skills`   | `load_flyout_skills_filtered/3` | Yes            |
| `:prompts`  | `load_flyout_prompts/3`         | Yes            |
| `:canvas`   | `maybe_load_canvases/2`         | No             |
| `:notes`    | `load_flyout_notes/3`           | Yes            |
| `:files`    | File tree on section open       | Yes            |
| `:jobs`     | `maybe_load_jobs/2`             | Yes            |
| `:usage`    | —                               | —              |

Sessions, notes, agents, skills, and prompts are also re-fetched when `sidebar_project` changes (project switch triggers a reload).

### Dual-Page Sections

Sections with both a global and project-scoped page show a single clickable header combining icon + label in the flyout header. When no route exists, the header is rendered as a plain div:

```elixir
defp dual_page_section?(section),
  do: section in [:sessions, :tasks, :prompts, :notes, :skills, :agents, :jobs]
```

**Header behavior**:
- When a project route exists: icon + label wrapped in a single `<.link>` that navigates to the project-scoped route (e.g., `/projects/:id/sessions`, `/projects/:id/notes`)
- When no project route exists: rendered as a plain `<div>` (icon + label not clickable)

**Section icons** — determined by `section_icon/1` helper:
- `:chat` → `hero-chat-bubble-left-ellipsis`
- `:canvas` → `hero-squares-2x2`
- `:usage` → `hero-chart-bar`
- `:notifications` → `hero-bell`
- `:skills` → `hero-bolt`
- `:prompts` → `hero-document-text`
- `:jobs` → `hero-clock`
- `:files` → `hero-folder`
- `:notes` → `hero-pencil-square`
- `:teams` → `hero-users`
- `:sessions`, `:tasks`, `:agents` → `hero-list-bullet` (default fallback)

Route mappings:
- Sessions: `/projects/:id/sessions`
- Tasks: `/projects/:id/kanban`
- Prompts: `/projects/:id/prompts`
- Notes: `/projects/:id/notes`
- Skills: `/projects/:id/skills`
- Agents: `/projects/:id/agents`
- Teams: `/teams` (global only)
- Jobs: `/projects/:id/jobs`

Helper functions:
- `dual_page_section?/1` — determines if a section has both global and project-scoped pages
- `project_route_for/2` — returns the project-scoped path if available, or nil
- `section_icon/1` — returns the appropriate icon name for a given section

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

## Flyout Filter Actions

All filter interactions (search, pill toggles, dropdowns) are routed through `filter_actions.ex`, which handles event dispatch and state updates.

**FilterActions module** (`lib/eye_in_the_sky_web/components/rail/filter_actions.ex`):

The module provides handlers for all flyout filters. Event naming follows the pattern `handle_update_<section>_<field>` or `handle_set_<section>_<field>`:

| Event | Handler | Updates |
|-------|---------|---------|
| `update_session_search` | `handle_update_session_search/2` | `:session_filter` |
| `set_session_show` | `handle_set_session_show/2` | `:session_show` (20/active) |
| `set_session_sort` | `handle_set_session_sort/2` | `:session_sort` |
| `update_task_search` | `handle_update_task_search/2` | `:task_search` |
| `set_task_state_id` | `handle_set_task_state_id/2` | `:task_state_id` (toggleable) |
| `update_note_search` | `handle_update_note_search/2` | `:note_search` |
| `set_note_parent_type` | `handle_set_note_parent_type/2` | `:note_parent_type` (toggleable) |
| `update_agent_search` | `handle_update_agent_search/2` | `:agent_search` |
| `set_agent_scope` | `handle_set_agent_scope/2` | `:agent_scope` (toggleable) |
| `update_skill_search` | `handle_update_skill_search/2` | `:skill_search` |
| `set_skill_scope` | `handle_set_skill_scope/2` | `:skill_scope` (toggleable) |
| `update_prompt_search` | `handle_update_prompt_search/2` | `:prompt_search` |
| `set_prompt_scope` | `handle_set_prompt_scope/2` | `:prompt_scope` (toggleable) |
| `update_team_search` | `handle_update_team_search/2` | `:team_search` |
| `set_team_status` | `handle_set_team_status/2` | `:team_status` (toggleable) |

**Toggleable pills**: Clicking an active pill clears the filter; clicking an inactive pill sets it. This is handled uniformly in filter_actions.ex.

**Loader re-trigger**: After each filter update, the corresponding `maybe_load_*` or `load_flyout_*` function is called to re-fetch data with the new filters applied.

---

## Theming and Color Tokens

The rail and flyout use CSS custom properties for consistent theming across light and dark modes:

**Surface token**: `--surface-sidebar` controls the rail and flyout background color:
- **Light mode** (default): `var(--surface-sidebar)` → DaisyUI `base-100` (lightest step)
- **Dark mode** (`[data-theme="dark"]`): `--surface-sidebar: #0a0a0a` (DaisyUI `base-300`, darkest step)

**Why base-300 in dark mode**: In dark mode, DaisyUI `base-200` is lighter than `base-100` (the canvas/page background). Using `base-200` would make the sidebar brighter than the content area, breaking visual hierarchy. `base-300` (darkest step) provides proper contrast.

**Applied to**:
- `.rail` element (`rail.ex`)
- `.flyout` container (`flyout.ex`)

---

## UI Patterns

### Flyout Filter Pills (Toggleable)

Filter pills appear in the filter zone of each flyout section. The pattern is uniform across all sections:

```heex
<!-- Example: task state pills -->
<div class="flex gap-1 flex-wrap">
  <%= for state <- @task_states do %>
    <button
      phx-click="set_task_state_id"
      phx-value-state_id={state.id}
      class={["px-2 py-1 rounded text-xs", if @task_state_id == state.id, do: "bg-primary text-white", else: "bg-base-200"]}
    >
      <%= state.label %>
    </button>
  <% end %>
</div>
```

**Toggle behavior**:
- Clicking an active pill sends the filter value again, which `FilterActions` interprets as a toggle-off (clears the filter)
- Clicking an inactive pill sends the new value, setting it as active
- The handler checks: `if current_value == new_value, do: nil, else: new_value`

This pattern is applied to:
- Task state pills (To Do, In Progress, In Review, Done)
- Note parent type pills (Session, Task, Project)
- Agent scope pills (All, Global, Project)
- Skill scope pills (All, Global, Project)
- Prompt scope pills (All, Global, Project)
- Team status pills (Active, All, Archived)

### Inline Create Modals

Tasks and prompts sections feature inline `+` buttons that open modals with simple form fields:

**Task modal**:
```heex
<form phx-submit="create_task" class="space-y-2">
  <input type="text" name="title" placeholder="Task title" required />
  <textarea name="body" placeholder="Description" rows="3"></textarea>
  <button type="submit">Create Task</button>
</form>
```

**Prompt modal**:
```heex
<form phx-submit="create_prompt" class="space-y-2">
  <input type="text" name="title" placeholder="Prompt title" required />
  <textarea name="body" placeholder="Prompt text" rows="3"></textarea>
  <button type="submit">Create Prompt</button>
</form>
```

**Form pattern**:
- Values are read from `params` on submit (no intermediate assigns for form fields)
- On success, the parent context creates the record and reloads the flyout list
- Modal is cleared and closed after successful submission

### Icon Consolidation

All icons in the rail and flyout use **custom_icon/1 or the standard `.icon` component** (from core_components.ex):

- **Lucide icons** (e.g., `kanban`, `globe`): use `.custom_icon` — these are consolidated inline SVGs to reduce imports
- **Heroicons** (e.g., `hero-list-bullet`, `hero-plus-mini`): use `.icon` — standard Heroicons fallback

Do NOT use raw inline SVGs elsewhere. Add new icons to `custom_icon/1` in core_components.ex.

**Section-specific icons**:
- **Skills section header**: `hero-bolt`
- **Skill rows**: `hero-bolt` (for skills from source field) or `hero-slash` (for slash commands)

### Bulk-Select UX (Sessions, Notes, Tasks)

Hover-reveal checkbox pattern used across list views:

- **Checkbox visibility**: hidden by default; appears on hover (`group-hover:flex`) and when select mode is active
- **Select mode activation**: clicking any checkbox enters select mode; subsequent clicks toggle selection for that row
- **Select-all**: indeterminate checkbox at top selects/deselects all visible rows
- **Row behavior in select mode**: clicking a row toggles its checkbox instead of navigating (prevented by event handler)
- **Exit select mode**: X button in bulk toolbar exits and clears selection
- **Bulk toolbar**: shown only when select_mode is true and rows are selected; includes select count and delete action

Related components:
- `NotesList` (`notes_list.ex`) — bulk delete for notes, with toolbar
- `ProjectSessionsTable` — bulk delete for sessions
- `TaskCardListRow` — individual row handling for task selection

---

## Known Gotchas

1. **`transition-all` flicker** — do not put `transition-all` inside stream items. CSS transitions replay from initial state (e.g. opacity-0) on stream reinsert, causing visible flicker.

2. **`phx-update="ignore"` on dropdowns and details** — use with a stable `id` on the element root. morphdom only syncs `data-*` attributes on ignored elements; `open` and other attributes are preserved. Applied to:
   - Dropdown menus (e.g., session sort, notes filter)
   - Details elements (e.g., skills section expand-in-place, notes small-note popups)

3. **DM Live sidebar_tab** — `DmLive` sets `sidebar_tab: :sessions`. Navigating to a DM does not change the active section.

4. **Archived task leakage** — tasks context must filter archived tasks at query time; the rail does not filter them after the fact.

5. **nil project_id Ecto warning** — some queries emit a warning when `project_id: nil` is passed. Always guard: `if project, do: Keyword.put(opts, :project_id, project.id), else: opts`.

6. **Canvas routes in :app live_session** — canvas pages mount inside the same `:app` live session, so the rail persists across canvas navigation. Canvas URLs do not carry `?project_id=X`; project context is not recovered from URL on canvas pages. Project selection is preserved via localStorage fallback.

7. **`sidebar_project: nil` does not clear the rail's project (within same LV process)** — the nil-guard in `update/2` preserves the locally held project within a LiveView process. Across LiveView navigation, persistence is now handled by localStorage (see Project Persistence section above).

8. **Rail LiveComponent state is not route-durable** — LiveComponent state only survives within the current parent LiveView process. Cross-route persistence is handled via URL params (canvas focus), localStorage (project selection), or maintained in contexts.

9. **`phx-change` on bare inputs is unreliable** — bare inputs (no form wrapper) only fire `phx-change` on blur. Use `phx-keyup` + `phx-debounce="300"` for real-time filtering. Applied to: session name filter, task search input, all flyout search inputs.

10. **Filter state preservation across toggles** — when user toggles the flyout closed and opens it again, filter/search state is preserved. This is intentional for UX but means clearing a search is a deliberate user action, not a side effect of navigation.

11. **FileActions module** — file event handlers (`handle_event` for file operations) were extracted to `lib/eye_in_the_sky_web/components/rail/file_actions.ex`. Rail.ex delegates file events to this module to keep the main component lean. Import and use the module as needed.

12. **FilterActions module** — all flyout filter interactions (search, pill toggles, dropdowns) are routed through `lib/eye_in_the_sky_web/components/rail/filter_actions.ex`. This keeps rail.ex lean and provides a single place to update filter logic and state.

13. **Icon consolidation via custom_icon/1** — inline SVGs for Lucide icons are consolidated in the `custom_icon/1` component (core_components.ex). Always use `.custom_icon` for new Lucide icons instead of raw SVG. Use `.icon` for Heroicons.

14. **File refresh preserves expanded state** — when the user clicks the refresh button in the files flyout, the tree re-reads root nodes and re-fetches children for all currently expanded paths. Paths that no longer exist on disk are pruned from the expanded set. This preserves the expanded view context and prevents broken intermediate states (expanded-but-empty directories).

15. **Agent prefill via data attributes** — clicking an agent row in the agents flyout opens the New Session form with that agent pre-filled. The agent row uses `data-prefill-slug` and `data-prefill-label` attributes; `AgentCombobox` reads these on mount and pre-selects the agent in the dropdown.

16. **Skills flyout details preservation** — the skills section uses `phx-update="ignore"` on the details element wrapping each skill row. This preserves the `open` state across re-renders when the skills list is reloaded (e.g., when search/filter changes).

17. **Notes expand-in-place pattern** — small notes (< 200 bytes) render as expandable `<details>` elements instead of navigating to the edit page. Large notes (≥ 200 bytes) provide an "Edit →" link within the expanded view that navigates to `/notes/:id/edit`. The expansion is in-place, preserving list scroll position.
