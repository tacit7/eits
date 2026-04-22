# Kanban Board

The kanban board is a project-scoped task management view at `/projects/:id/kanban`. It provides drag-and-drop columns, filtering, bulk operations, and task detail editing.

## Columns

Four workflow states by default:

| Column      | Color   |
|-------------|---------|
| To Do       | Gray    |
| In Progress | Blue    |
| In Review   | Amber   |
| Done        | Green   |

Columns are **drag-reorderable** using the grip handle next to the column name. Reordering changes display position only; state IDs (used by API/CLI) remain the same.

## Creating Tasks

**New Task button** (top right): Opens a drawer with title, description, status, priority, due date, and tags fields.

**Quick add** (bottom of each column): Click "+ Add task" to type a title inline and press Enter. Creates a task in that column with no priority.

## Task Cards

Each card shows:

- **Title** (strikethrough if completed)
- **Priority badge**: High (red), Med (amber), Low (blue)
- **Description** preview (2-line clamp)
- **Checklist progress bar** (green when all done, blue otherwise) with done/total count
- **Aging indicator**: 7+ days idle (warning clock), 14+ days stale (error clock). Shown as left border accent + label.
- **Tags** (up to 2, with color dots)
- **Due date**: Shows "Today", "Tomorrow", "Overdue", or formatted date
- **Notes count** (chat bubble icon)
- **UUID** (first 8 chars, click clipboard icon to copy)

Click a card to open the **task detail drawer**.

## Task Detail Drawer

Right-side slide-over panel for full task editing:

- **Title**: Inline editable text field
- **Status**: Dropdown (To Do, In Progress, In Review, Done)
- **Priority**: Dropdown (None, Low, Medium, High)
- **Due date**: Date picker with overdue/today indicators
- **Tags**: Comma-separated text input
- **Description**: Multi-line textarea
- **Checklist**: Add items, toggle completion, delete items. Progress bar shows completion percentage.
- **Annotations**: Read existing notes, add new ones via textarea
- **Footer actions**: Save, Start Agent, Copy to Project, Archive, Delete

## Filtering

### Search
Type 2 or more characters in the search bar to filter tasks by title/description (full-text search).

**Search behavior:**
- Minimum 2 characters required to start filtering
- Searches across task title and description fields
- Real-time results as you type
- Hint text shows search instruction when field is empty
- Partial matches supported (substring and word matching)

### Priority Filters
Click High/Med/Low chips to filter by priority. Click again to deselect.

### Tag Filters
Click tag chips to filter. Multiple tags can be selected:
- **AND mode** (default): Shows tasks that have ALL selected tags
- **OR mode**: Shows tasks that have ANY selected tag
- Toggle between AND/OR appears when 2+ tags are selected
- Each tag chip shows a task count

Click the color dot next to a tag name to cycle through 8 colors (gray, red, amber, green, blue, purple, pink, cyan).

**Clear** button removes all active filters.

### Visibility Toggles

Three toggle buttons in the toolbar:

- **Done** (check circle): Show/hide tasks with `completed_at` set
- **Archived** (archive box): Show/hide archived tasks
- **Select** (checkbox): Enter bulk selection mode

## Bulk Operations

1. Click the **Select** toggle to enter bulk mode
2. Checkboxes appear on each card. Click cards to select/deselect.
3. **Select All** checkbox on column headers selects/deselects entire column
4. Action bar appears showing count of selected tasks:
   - **Move to**: Buttons for each column (moves all selected tasks)
   - **Archive**: Archives all selected tasks
   - **Delete**: Deletes all selected (with confirmation dialog)

## Drag and Drop

### Cards
Drag cards within a column to reorder, or between columns to change state. Uses SortableJS via the `SortableKanban` hook.

### Columns
Drag columns by the grip handle (bars icon) next to the column name to reorder. Uses SortableJS via the `SortableColumns` hook. Column position changes are persisted to the database.

## Spawning Agents

From the task detail drawer, click **Start Agent** to spawn a Claude agent for the task. The agent receives the task title and description as its prompt. The resulting session is linked to the task.

## Copying Tasks

In the task detail drawer footer, click the document-duplicate icon to copy a task to another project. Copies title, description, priority, and tags. The copy starts in "To Do" state.

## Real-Time Updates

The board subscribes to PubSub on `tasks:{project_id}`. When tasks are created, updated, or deleted via API/CLI/other sessions, the board reloads automatically.

## CLI / API Integration

Tasks can also be managed via the `eits` CLI or REST API:

```bash
# Create a task
eits tasks create --title "Fix login bug" --description "Details..." --project 1

# Move to In Progress
eits tasks update <task_id> --state 2

# Move to Done
eits tasks update <task_id> --state 3

# Archive
eits tasks archive <task_id>
```

State IDs are stable regardless of column display order:
- 1 = To Do
- 2 = In Progress
- 4 = In Review
- 3 = Done

## Column Task Count

Each column header displays the current task count for that column. Task counts are real-time and update as tasks are created, moved, or archived.

## Navigation Between Views

### Sidebar Task Links

The sidebar "Tasks" nav item links directly to the kanban board (`/projects/:id/kanban`) instead of the list view. The kanban tab highlights as active for both `:tasks` and `:kanban` routes.

**File**: `lib/eye_in_the_sky_web/components/sidebar/projects_section.ex` — `panel_nav_item` href changed from `/projects/:id/tasks` to `/projects/:id/kanban`.

### Kanban Toolbar List View Link

The kanban toolbar includes a "List" button that navigates to the task list view (`/projects/:id/tasks`), allowing users to switch between kanban and list layouts. The toolbar receives `project_id` as a required attr.

**File**: `lib/eye_in_the_sky_web/components/kanban_toolbar.ex`

### Related commits

- `a5824f3` — sidebar tasks links to kanban; kanban toolbar has list view link

## Component Improvements

### KanbanCard Helper Extraction

The `KanbanCard` component (`lib/eye_in_the_sky_web/components/task_card/kanban_card.ex`) was refactored to:

- **Deduplicate `task_id`**: The `task.uuid || to_string(task.id)` expression was computed once in `kanban_card/1` and passed as a `task_id` assign to all inner components, eliminating repeated derivation across `toggle_task_complete`, title click, context menu, and footer.
- **Extract `resolve_dm_session/1`**: The inline pattern match that finds a task's first associated session was extracted into a named helper, clarifying the intent and making it reusable.

**Commit**: `60fc345`

### Active Filter Count Assign

The `active_filter_count` computation was moved out of the kanban template (inline `<% %>` block) into a dedicated `FilterHandlers.assign_filter_count/1` function. This keeps the template declarative and ensures the count updates correctly after every filter change.

**Files**:
- `lib/eye_in_the_sky_web/live/project_live/kanban.ex` — template uses `@active_filter_count` assign
- `lib/eye_in_the_sky_web/live/project_live/kanban/filter_handlers.ex` — `assign_filter_count/1` and `count_active_filters/1`

**Commit**: `cb05a1d`

## Event Consolidation

### Agent Working/Stopped Events

Duplicate `handle_info` clauses for `{:agent_working, ...}` and `{:agent_stopped, ...}` with the 3-tuple pattern (`{event, session_ref, session_int_id}`) were removed from the kanban LiveView. The remaining handlers use the map-based message format and delegate to `handle_agent_stopped/3`, which handles both the MapSet update and task reload.

**File**: `lib/eye_in_the_sky_web/live/project_live/kanban.ex`
**Commit**: `0351df5`

## Mobile Drawer Fixes

The task detail drawer and new agent drawer received mobile touch-target improvements:

- **Task detail drawer**: Close button uses `min-h-[44px] min-w-[44px]` with flexbox centering for reliable touch targets.
- **New agent drawer**: Uses `w-full max-w-sm` instead of fixed `w-96` to fit smaller screens.

**Files**:
- `lib/eye_in_the_sky_web/components/task_detail_drawer.ex`
- `lib/eye_in_the_sky_web/components/new_agent_drawer.ex`

**Commit**: `3b6a053`

## File Locations

| Component | Path |
|-----------|------|
| LiveView | `lib/eye_in_the_sky_web/live/project_live/kanban.ex` |
| Filter Handlers | `lib/eye_in_the_sky_web/live/project_live/kanban/filter_handlers.ex` |
| Kanban Toolbar | `lib/eye_in_the_sky_web/components/kanban_toolbar.ex` |
| Kanban Card | `lib/eye_in_the_sky_web/components/task_card/kanban_card.ex` |
| Detail Drawer | `lib/eye_in_the_sky_web/components/task_detail_drawer.ex` |
| New Task Drawer | `lib/eye_in_the_sky_web/components/new_task_drawer.ex` |
| New Agent Drawer | `lib/eye_in_the_sky_web/components/new_agent_drawer.ex` |
| Sidebar Projects | `lib/eye_in_the_sky_web/components/sidebar/projects_section.ex` |
| View Helpers | `lib/eye_in_the_sky_web/helpers/view_helpers.ex` |
| Tasks Context | `lib/eye_in_the_sky_web/tasks.ex` |
| Task Schema | `lib/eye_in_the_sky_web/tasks/task.ex` |
| ChecklistItem | `lib/eye_in_the_sky_web/tasks/checklist_item.ex` |
| JS Hooks | `assets/js/app.js` (SortableKanban, SortableColumns) |
