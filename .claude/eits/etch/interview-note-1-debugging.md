**Tags**: debugging, elixir, phoenix, ecto, migration, type-safety

## Debugged cascading type errors after database schema migration (Elixir/Phoenix, Eye in the Sky)

**Situation**: I was working on Eye in the Sky, a Phoenix/Elixir monitoring web app with 33 database tables. We'd just completed a major schema migration from UUID TEXT primary keys to INTEGER auto-increment PKs (to improve performance and usability). The SQL migration succeeded, all 33 schemas were updated, and the app compiled with zero errors. However, when I tried to load pages in the browser, I hit cascading runtime errors across multiple LiveViews.

**Task**: The first error was `FunctionClauseError: no function clause matching String.slice(86, 0..7)` on the kanban board page. The error showed that `String.slice/2` was being called with an integer (86) instead of a string. This was just the tip of the iceberg - the migration had introduced type mismatches throughout the codebase that weren't caught at compile time because Ecto uses runtime type casting. I needed to systematically find and fix all UUID-to-integer type mismatches across the entire application.

**Action**: I took a systematic debugging approach:

1. **Root cause analysis**: The error trace pointed to `task_card.ex:86` which had `String.slice(@task.id, 0..7)`. The code expected a UUID string to display a shortened ID, but `@task.id` was now an integer. This revealed the pattern: display code was using `.id` fields that were now integers instead of UUIDs.

2. **Schema verification**: I searched for any schemas that still had the old configuration. Found that `Agent` and `Prompt` schemas had been missed during the initial migration - they still had `@primary_key {:id, :string, autogenerate: false}` and `@foreign_key_type :string`. Fixed both to use `@primary_key {:id, :id, autogenerate: true}` and added `field :uuid, :string`.

3. **Template fixes**: Updated all display code to use `.uuid` instead of `.id`:
   - `String.slice(@task.id, ...)` → `String.slice(@task.uuid, ...)`
   - `data-copy={@task.id}` → `data-copy={@task.uuid}` (for clipboard)
   - `phx-value-task_id={@task.id}` → `phx-value-task_id={@task.uuid}` (event params)

4. **Event handler updates**: Event handlers receiving UUID strings from templates needed to use `_by_uuid!` functions:
   - `Tasks.get_task!(task_id)` → `Tasks.get_task_by_uuid!(task_id)`
   - SQL queries needed integer IDs: `DELETE FROM task_tags WHERE task_id = ?` with `task.id` instead of the UUID param

5. **Second-wave error**: After fixing the kanban board, the DM (Direct Message) page failed with `value "ce0c166c..." in where cannot be cast to type :integer`. The mount function was passing a UUID from the URL to `list_recent_messages(session_id)`, but the function expected an integer. Fixed by adding a resolver: `Integer.parse(param)` with fallback to UUID lookup.

6. **Third-wave error**: Notes weren't showing up for sessions that had UUID-based parent_ids from before the migration. The query was only checking for integer parent_ids as strings. Fixed by updating all note queries to check both: `WHERE parent_id == to_string(id) OR parent_id == uuid`.

**Result**: After three rounds of systematic fixes across 6 files, all pages loaded successfully:
- Kanban board renders tasks with shortened UUIDs (#abc1234 instead of integers)
- DM page accepts both integer IDs (`/dm/33`) and UUIDs (`/dm/abc-123...`) in URLs
- Notes display correctly for both pre-migration (UUID parent_ids) and post-migration (integer parent_ids) data
- Zero compilation errors, zero runtime errors
- Learned to establish a clear pattern: UUIDs for display/URLs, integers for internal queries

**What I'd do differently**: I should have written a comprehensive test suite that exercised all LiveView pages before running the migration. Runtime type errors in Ecto are harder to catch than compile-time errors, so integration tests would have caught these issues before deploying. I'd also create a migration checklist that explicitly covers: schemas, associations, display templates, event handlers, and query functions.

**Interview questions this answers**:
- "Tell me about a time you debugged a complex, multi-layered issue"
- "Describe a situation where you had to trace an error through multiple system layers"
- "Tell me about a time when a seemingly simple change had unexpected consequences"
- "How do you approach systematic debugging when you don't know the full scope of the problem?"
