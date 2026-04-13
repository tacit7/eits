# Kanban Page Refactor Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Break the 819-line `kanban.ex` LiveView into focused components and shared helpers, targeting ~200 lines in the main LiveView.

**Architecture:** Extract the render template into 3 function components (toolbar, bulk action bar, kanban board). Extract bulk operation handlers into a shared helper module. Extract the copy-task-to-project logic into TasksHelpers. Move `update_filter` and `load_tasks` into KanbanFilters. The main LiveView becomes a thin orchestrator that wires assigns, delegates events, and composes components.

**Tech Stack:** Elixir/Phoenix LiveView, HEEx function components.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/eye_in_the_sky_web_web/components/kanban_toolbar.ex` | Search bar + action buttons (Done, Select, Filter, List, New Task) |
| Create | `lib/eye_in_the_sky_web_web/components/kanban_bulk_bar.ex` | Bulk action bar (move, archive, delete selected) |
| Create | `lib/eye_in_the_sky_web_web/components/kanban_board.ex` | Columns, cards, quick-add, scroll dots |
| Modify | `lib/eye_in_the_sky_web_web/live/shared/tasks_helpers.ex` | Add `handle_copy_task_to_project/3` |
| Modify | `lib/eye_in_the_sky_web_web/live/shared/kanban_filters.ex` | Add `load_tasks/1`, `update_filter/2`, move `state_dot_color/1` here |
| Create | `lib/eye_in_the_sky_web_web/live/shared/bulk_helpers.ex` | Bulk mode event handlers (toggle, select, move, archive, delete) |
| Modify | `lib/eye_in_the_sky_web_web/live/project_live/kanban.ex` | Thin orchestrator — mount, imports, event delegation, render |
| Modify | `test/eye_in_the_sky_web_web/live/project_live/kanban_test.exs` | Verify existing tests still pass after refactor |

## Line Count Targets

| File | Current | Target |
|------|---------|--------|
| `kanban.ex` (main LiveView) | 819 | ~200 |
| `kanban_toolbar.ex` | — | ~70 |
| `kanban_bulk_bar.ex` | — | ~45 |
| `kanban_board.ex` | — | ~160 |
| `bulk_helpers.ex` | — | ~90 |
| `kanban_filters.ex` | 133 | ~210 (absorbs load_tasks, update_filter, state_dot_color) |
| `tasks_helpers.ex` | 219 | ~255 (absorbs copy_task_to_project) |

---

## Task 1: Extract `kanban_toolbar` Component

**Files:**
- Create: `lib/eye_in_the_sky_web_web/components/kanban_toolbar.ex`
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/kanban.ex:506-580`

This is the search bar and action buttons section of the render template.

- [ ] **Step 1: Create the component file**

```elixir
defmodule EyeInTheSkyWebWeb.Components.KanbanToolbar do
  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents

  attr :search_query, :string, required: true
  attr :show_completed, :boolean, required: true
  attr :bulk_mode, :boolean, required: true
  attr :active_filter_count, :integer, required: true
  attr :project, :map, required: true
  attr :show_filter_drawer, :boolean, required: true

  def kanban_toolbar(assigns) do
    ~H"""
    <div class="mb-4 flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3 sticky top-0 z-10 bg-base-100 -mx-4 px-4 sm:-mx-6 sm:px-6 pt-1 pb-2 md:static md:mx-0 md:px-0 md:pt-0 md:pb-0 md:bg-transparent">
      <%-- Copy lines 514-579 from kanban.ex, replacing @-references with assigns --%>
      <%-- The search form, Done/Select/Filter/List/New Task buttons --%>
    </div>
    """
  end
end
```

- [ ] **Step 2: Replace the inline toolbar in kanban.ex render with the component call**

```heex
<.kanban_toolbar
  search_query={@search_query}
  show_completed={@show_completed}
  bulk_mode={@bulk_mode}
  active_filter_count={active_filter_count}
  project={@project}
  show_filter_drawer={@show_filter_drawer}
/>
```

- [ ] **Step 3: Add import to kanban.ex**

```elixir
import EyeInTheSkyWebWeb.Components.KanbanToolbar, only: [kanban_toolbar: 1]
```

- [ ] **Step 4: Run `mix compile --warnings-as-errors`**

- [ ] **Step 5: Run tests**

Run: `mix test test/eye_in_the_sky_web_web/live/project_live/kanban_test.exs`

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/kanban_toolbar.ex lib/eye_in_the_sky_web_web/live/project_live/kanban.ex
git commit -m "refactor: extract KanbanToolbar component from kanban LiveView"
```

---

## Task 2: Extract `kanban_bulk_bar` Component

**Files:**
- Create: `lib/eye_in_the_sky_web_web/components/kanban_bulk_bar.ex`
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/kanban.ex:582-619`

The bulk action bar that appears when tasks are selected.

- [ ] **Step 1: Create the component file**

```elixir
defmodule EyeInTheSkyWebWeb.Components.KanbanBulkBar do
  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents

  attr :bulk_mode, :boolean, required: true
  attr :selected_tasks, :any, required: true
  attr :workflow_states, :list, required: true

  def kanban_bulk_bar(assigns) do
    ~H"""
    <%= if @bulk_mode and MapSet.size(@selected_tasks) > 0 do %>
      <%-- Copy lines 584-618 from kanban.ex --%>
    <% end %>
    """
  end
end
```

Move `state_dot_color/1` to `KanbanFilters` (shared) since it's used by both the bulk bar and the board.

- [ ] **Step 2: Replace inline bulk bar in kanban.ex render with component call**

- [ ] **Step 3: Run `mix compile --warnings-as-errors` and tests**

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/kanban_bulk_bar.ex lib/eye_in_the_sky_web_web/live/project_live/kanban.ex
git commit -m "refactor: extract KanbanBulkBar component from kanban LiveView"
```

---

## Task 3: Extract `kanban_board` Component

**Files:**
- Create: `lib/eye_in_the_sky_web_web/components/kanban_board.ex`
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/kanban.ex:621-770`

The columns grid, task cards, quick-add inputs, and mobile scroll dots. This is the biggest template extraction (~150 lines).

- [ ] **Step 1: Create the component file**

```elixir
defmodule EyeInTheSkyWebWeb.Components.KanbanBoard do
  use Phoenix.Component
  import EyeInTheSkyWebWeb.CoreComponents
  import EyeInTheSkyWebWeb.Components.TaskCard, only: [task_card: 1]

  attr :workflow_states, :list, required: true
  attr :tasks_by_state, :map, required: true
  attr :bulk_mode, :boolean, required: true
  attr :selected_tasks, :any, required: true
  attr :quick_add_column, :any, required: true
  attr :working_session_ids, :any, required: true

  def kanban_board(assigns) do
    ~H"""
    <div class="flex-1 min-h-0 overflow-x-auto" id="kanban-scroll" phx-hook="KanbanScrollDots" data-column-count={length(@workflow_states)}>
      <%-- Copy lines 628-769 from kanban.ex --%>
    </div>
    """
  end
end
```

- [ ] **Step 2: Replace inline board in kanban.ex render with component call**

- [ ] **Step 3: Import `state_dot_color/1` from KanbanFilters into the new component**

```elixir
import EyeInTheSkyWebWeb.Live.Shared.KanbanFilters, only: [state_dot_color: 1]
```

Note: `kanban_bulk_bar.ex` (Task 2) also needs this same import.

- [ ] **Step 4: Run `mix compile --warnings-as-errors` and tests**

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky_web_web/components/kanban_board.ex lib/eye_in_the_sky_web_web/live/project_live/kanban.ex
git commit -m "refactor: extract KanbanBoard component from kanban LiveView"
```

---

## Task 4: Extract Bulk Helpers

**Files:**
- Create: `lib/eye_in_the_sky_web_web/live/shared/bulk_helpers.ex`
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/kanban.ex:168-258`

Move all 5 bulk event handlers (`toggle_bulk_mode`, `toggle_select_task`, `select_all_column`, `bulk_move`, `bulk_archive`, `bulk_delete`) into a shared helper module that any LiveView can import.

- [ ] **Step 1: Create the helper module**

```elixir
defmodule EyeInTheSkyWebWeb.Live.Shared.BulkHelpers do
  import EyeInTheSkyWebWeb.ControllerHelpers, only: [parse_int: 2]
  alias EyeInTheSkyWeb.Tasks

  def handle_toggle_bulk_mode(socket) do
    {:noreply,
     socket
     |> Phoenix.Component.assign(:bulk_mode, !socket.assigns.bulk_mode)
     |> Phoenix.Component.assign(:selected_tasks, MapSet.new())}
  end

  def handle_toggle_select_task(%{"task-uuid" => uuid}, socket) do
    # ... move logic from kanban.ex lines 177-186
  end
  def handle_toggle_select_task(_params, socket), do: {:noreply, socket}

  def handle_select_all_column(%{"state-id" => state_id_str}, socket) do
    # ... move logic from kanban.ex lines 194-211
  end

  def handle_bulk_move(%{"state_id" => state_id_str}, socket, reload_fn) do
    # ... move logic from kanban.ex lines 214-226
  end

  def handle_bulk_archive(socket, reload_fn) do
    # ... move logic from kanban.ex lines 229-242
  end

  def handle_bulk_delete(socket, reload_fn) do
    # ... move logic from kanban.ex lines 245-258
    # NOTE: must accept reload_fn — current code calls load_tasks(socket) internally
  end
end
```

**Important:** All three batch handlers (`bulk_move`, `bulk_archive`, `bulk_delete`) must accept `reload_fn` as a parameter since the current code calls `load_tasks(socket)` inside each one. The caller passes `&load_tasks/1`.

- [ ] **Step 2: Update kanban.ex to import and delegate**

```elixir
import EyeInTheSkyWebWeb.Live.Shared.BulkHelpers

# Replace each handle_event with delegation:
def handle_event("toggle_bulk_mode", _params, socket),
  do: handle_toggle_bulk_mode(socket)

def handle_event("toggle_select_task", params, socket),
  do: handle_toggle_select_task(params, socket)
# ... etc
```

- [ ] **Step 3: Run `mix compile --warnings-as-errors` and tests**

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/shared/bulk_helpers.ex lib/eye_in_the_sky_web_web/live/project_live/kanban.ex
git commit -m "refactor: extract bulk operation handlers into BulkHelpers"
```

---

## Task 5: Move `load_tasks`, `update_filter`, `state_dot_color` into KanbanFilters

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/shared/kanban_filters.ex`
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/kanban.ex:423-498`

The `load_tasks/1` function (lines 423-456), `update_filter/2` (lines 458-495), and `state_dot_color/1` (lines 497-498) are pure filter/data logic that belongs in KanbanFilters.

**Critical:** These are currently `defp` (private) in kanban.ex. They must become `def` (public) when moved to KanbanFilters, otherwise callers will get `undefined function` errors.

- [ ] **Step 1: Move `load_tasks/1` to KanbanFilters**

Add to `kanban_filters.ex` as `def load_tasks(socket)`. It depends on Tasks, Projects, Notes contexts; add those aliases.

- [ ] **Step 2: Move `update_filter/2` to KanbanFilters**

All 5 clauses (due_date, activity, priority, tag, tag_mode) plus the catch-all.

- [ ] **Step 3: Move `state_dot_color/1` to KanbanFilters**

Used by KanbanBulkBar and KanbanBoard components; making it public in KanbanFilters lets both import it.

- [ ] **Step 4: Update imports in kanban.ex, kanban_board.ex, kanban_bulk_bar.ex**

```elixir
# kanban.ex — add to existing KanbanFilters import:
import EyeInTheSkyWebWeb.Live.Shared.KanbanFilters,
  only: [apply_filters: 1, parse_due_date_filter: 1, parse_activity_filter: 1,
         load_tasks: 1, update_filter: 2, state_dot_color: 1]
```

- [ ] **Step 5: Run `mix compile --warnings-as-errors` and tests**

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/shared/kanban_filters.ex lib/eye_in_the_sky_web_web/live/project_live/kanban.ex
git commit -m "refactor: move load_tasks, update_filter, state_dot_color into KanbanFilters"
```

---

## Task 6: Move `copy_task_to_project` into TasksHelpers

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/shared/tasks_helpers.ex`
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/kanban.ex:127-162`

- [ ] **Step 1: Add `handle_copy_task_to_project/2` to TasksHelpers**

Move the 35-line handler. It takes `params` and `socket`, returns `{:noreply, socket}`.

**Required imports/aliases to add in TasksHelpers:**
- `import EyeInTheSkyWebWeb.ControllerHelpers, only: [parse_int: 2]` (if not already imported)
- `alias EyeInTheSkyWeb.Tasks.WorkflowState` (for `WorkflowState.todo_id()`)
- `alias EyeInTheSkyWeb.Projects` (for `Projects.get_project!/1`)

- [ ] **Step 2: Delegate from kanban.ex**

```elixir
def handle_event("copy_task_to_project", params, socket),
  do: handle_copy_task_to_project(params, socket)
```

- [ ] **Step 3: Run `mix compile --warnings-as-errors` and tests**

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky_web_web/live/shared/tasks_helpers.ex lib/eye_in_the_sky_web_web/live/project_live/kanban.ex
git commit -m "refactor: move copy_task_to_project into TasksHelpers"
```

---

## Task 7: Final Cleanup and Verification

**Files:**
- Modify: `lib/eye_in_the_sky_web_web/live/project_live/kanban.ex`

- [ ] **Step 1: Remove unused aliases and imports from kanban.ex**

- [ ] **Step 2: Verify kanban.ex is ~200 lines or less**

Run: `wc -l lib/eye_in_the_sky_web_web/live/project_live/kanban.ex`

- [ ] **Step 3: Run full test suite**

Run: `mix test test/eye_in_the_sky_web_web/live/project_live/kanban_test.exs`

- [ ] **Step 4: Run `mix compile --warnings-as-errors`**

- [ ] **Step 5: Final commit**

```bash
git commit -m "refactor: clean up kanban.ex imports after extraction"
```

---

## Execution Notes

- **Order matters:** Tasks 1-3 (template extraction) should come first because they're the biggest wins and least risky. Tasks 4-6 (logic extraction) build on the cleaner file. Task 7 is cleanup.
- **Each task is independently committable and testable.** If any step breaks tests, revert that task only.
- **No behavior changes.** This is a pure structural refactor; the UI and functionality must remain identical.
- **`@tag_colors` module attribute** stays in kanban.ex (or moves to wherever `cycle_tag_color` lives). Since it's only used by one event handler, it can stay in the main LiveView.
- **`archive_column` handler** (lines 362-369) intentionally stays in kanban.ex — it's a column-level operation, not bulk mode, and not reusable elsewhere.
- **`active_filter_count`** is computed inline in the render function (line 534-536) as a HEEx let-binding. When extracting Task 1, compute it in the kanban.ex render function _before_ the `<.kanban_toolbar>` call and pass it as an attr. Do not compute it inside the toolbar component.
