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
eits tasks update <task_id> --state 4

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

## File Locations

| Component | Path |
|-----------|------|
| LiveView | `lib/eye_in_the_sky_web_web/live/project_live/kanban.ex` |
| Task Card | `lib/eye_in_the_sky_web_web/components/task_card.ex` |
| Detail Drawer | `lib/eye_in_the_sky_web_web/components/task_detail_drawer.ex` |
| New Task Drawer | `lib/eye_in_the_sky_web_web/components/new_task_drawer.ex` |
| View Helpers | `lib/eye_in_the_sky_web_web/helpers/view_helpers.ex` |
| Tasks Context | `lib/eye_in_the_sky_web/tasks.ex` |
| Task Schema | `lib/eye_in_the_sky_web/tasks/task.ex` |
| ChecklistItem | `lib/eye_in_the_sky_web/tasks/checklist_item.ex` |
| JS Hooks | `assets/js/app.js` (SortableKanban, SortableColumns) |
