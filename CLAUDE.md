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

Three FTS5 virtual tables in eits.db provide full-text search using **external content tables** (stores only the index, not duplicate data). Triggers keep them in sync.

**`sessions_fts`** - Indexes session name and description from sessions table.

```sql
CREATE VIRTUAL TABLE sessions_fts USING fts5(
  name, description,
  content=sessions,
  content_rowid=id
);
```

Triggers: `sessions_fts_insert`, `sessions_fts_update`, `sessions_fts_delete`
- Keeps FTS index in sync with sessions table changes
- Uses external content: FTS5 stores only the index, data lives in sessions table
- Join key: `rowid` (FTS5 rowid matches sessions.id via content_rowid)

**`task_search`** - Indexes task title and description from tasks table.

```sql
CREATE VIRTUAL TABLE task_search USING fts5(
  title, description,
  content=tasks,
  content_rowid=id,
  tokenize='porter'
);
```

Triggers: `task_search_insert`, `task_search_update`, `task_search_delete`
- Keeps FTS index in sync with tasks table changes
- Uses external content: FTS5 stores only the index, data lives in tasks table
- Join key: `rowid` (FTS5 rowid matches tasks.id via content_rowid)

**`notes_fts`** - Indexes note title and body from notes table.

```sql
CREATE VIRTUAL TABLE notes_fts USING fts5(
  title, body,
  content=notes,
  content_rowid=id
);
```

Triggers: `notes_fts_insert`, `notes_fts_update`, `notes_fts_delete`
- Keeps FTS index in sync with notes table changes
- Uses external content: FTS5 stores only the index, data lives in notes table
- Join key: `rowid` (FTS5 rowid matches notes.id via content_rowid)

### FTS5.search Module

`lib/eye_in_the_sky_web/search/fts5.ex` provides a reusable search function. Key option: `join_key` specifies which FTS column to join on the main table's `id`. Defaults to `"rowid"`.

With external content tables, use `join_key: "rowid"` for all FTS5 searches.

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
