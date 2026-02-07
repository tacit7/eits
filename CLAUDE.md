# CLAUDE.md

This file provides guidance to Claude Code when working with the Eye in the Sky web application.

## Project Overview

Phoenix/Elixir web app that provides a monitoring UI for Eye in the Sky. Reads from a shared SQLite database owned by the Go MCP server. This project should NEVER create Ecto migrations; all schema changes go through the Go core or direct SQL.

## Build & Run

```bash
mix deps.get
mix phx.server          # Start dev server on https://localhost:4001
mix compile              # Compile only
```

Assets: `cd assets && npm install` for JS dependencies. Esbuild and Tailwind run as Phoenix watchers.

## Database

Single SQLite database at `~/.config/eye-in-the-sky/eits.db`. Configured in `config/dev.exs`. The Go MCP server owns the schema; this app is a read-heavy consumer.

**No migrations.** The `priv/repo/migrations/` directory should stay empty. Schema changes are applied by the Go core's embedded `schema.sql` or via direct `sqlite3` commands.

## Architecture

- `lib/eye_in_the_sky_web/` - Contexts (Sessions, Tasks, Agents, Projects, Notes, Prompts, Commits)
- `lib/eye_in_the_sky_web_web/` - Web layer (LiveViews, components, router)
- `lib/eye_in_the_sky_web/search/fts5.ex` - Reusable FTS5 search module with LIKE fallback

### FTS5 Full-Text Search

Two FTS5 virtual tables in eits.db provide full-text search. They do NOT use external content (`content=`); they store their own copy of indexed text. Triggers keep them in sync.

**`sessions_fts`** - Indexes session name, description, agent description, project name.

```sql
CREATE VIRTUAL TABLE sessions_fts USING fts5(
  session_id UNINDEXED, session_name, description,
  agent_id UNINDEXED, agent_description, project_name
);
```

Triggers: `sessions_fts_insert`, `sessions_fts_update`, `sessions_fts_delete`
- Insert trigger joins agents and projects tables to populate denormalized fields.
- Update trigger re-queries agent/project via subselects.
- Delete trigger removes by rowid.
- Join key: `rowid` (FTS5 implicit rowid matches sessions rowid).

**`task_search`** - Indexes task title and description.

```sql
CREATE VIRTUAL TABLE task_search USING fts5(
    task_id UNINDEXED, title, description, tokenize='porter'
);
```

Triggers: `task_search_insert`, `task_search_update`, `task_search_delete`
- Insert trigger copies task_id, title, description on new task.
- Update trigger fires on title/description changes; deletes old row, inserts new.
- Delete trigger removes by task_id.
- Join key: `task_id` (not rowid, because task IDs are UUIDs).

### FTS5.search Module

`lib/eye_in_the_sky_web/search/fts5.ex` provides a reusable search function. Key option: `join_key` specifies which FTS column to join on the main table's `id`. Defaults to `"rowid"`. Task search uses `join_key: "task_id"`.

If the FTS5 query fails (e.g., table doesn't exist), it falls back to ILIKE.

### Workflow States

The `workflow_states` table defines kanban columns. Current states:

| ID | Name        | Position | Color   |
|----|-------------|----------|---------|
| 1  | To Do       | 1        | #6B7280 |
| 2  | In Progress | 2        | #3B82F6 |
| 4  | In Review   | 3        | #F59E0B |
| 3  | Done        | 4        | #10B981 |

### Type Quirks

- Project PK is integer (`@primary_key {:id, :id, autogenerate: false}`) but Go MCP writes some foreign keys as text. Task `project_id` uses `type: :string` in the Ecto association to handle this.
- Agent `project_name` is a real DB column (not virtual), populated by Go.
