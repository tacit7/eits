# lib/ — Elixir Source Conventions

## Architecture

- `lib/eye_in_the_sky/` - OTP core: Repo, contexts (Sessions, Tasks, Agents, Projects, Notes, Prompts, Commits, Canvases, AgentDefinitions), search, scheduler
- `lib/eye_in_the_sky_web/` - Web layer: endpoint, router, plugs, LiveViews, components, controllers
- `lib/eye_in_the_sky/search/pg_search.ex` - Full-text search (`EyeInTheSky.Search.PgSearch`)
- `lib/eye_in_the_sky/sessions/queries.ex` - SessionQueries (Ecto-based session operations)

## Workspace Scope

Workspace-level LiveViews use a `Scope` struct injected by `WorkspaceLive.Hooks` on_mount. See [`docs/WORKSPACE_SCOPE.md`](../docs/WORKSPACE_SCOPE.md) for the full contract: Scope struct fields, cross-workspace ownership validation patterns (pin match in actions, MapSet guard in components), and canonical query functions.

## Schema Conventions

### Timestamp Types

All tables use `:utc_datetime_usec`. Use `DateTime.utc_now()` when setting timestamps programmatically. The `tasks` table uses `created_at`, **not** `inserted_at`.

### UUID Columns

Native PostgreSQL `uuid` type. Ecto handles encoding/decoding automatically — pass plain strings in queries. `source_uuid` tracks the originating session/agent UUID.

## Shared Helpers — Check Before Implementing

**Before writing any utility function, grep for it and check this table.** Re-implementing these is the most common source of duplication caught in audits.

| Need | Function | Module |
|------|----------|--------|
| Provider logo `<img src>` | `DmHelpers.provider_icon/1` | `components/dm_helpers.ex` |
| Provider logo CSS class | `DmHelpers.provider_icon_class/1` | `components/dm_helpers.ex` |
| Bulk op flash message | `BulkHelpers.build_bulk_flash/3` (opts: `verb:`, `entity:`, `destination:`) | `live/shared/bulk_helpers.ex` |
| String → integer (nil on fail) | `ControllerHelpers.parse_int/1` or `/2` | `helpers/controller_helpers.ex` |
| Session terminated? | `Sessions.terminated_statuses/0` → `~w(completed failed)` | `eye_in_the_sky/sessions.ex` |
| Status dot (UI component) | `<.status_dot status={atom}>` | `components/core_components.ex` |
| Status badge (UI component) | `<.status_badge status={atom}>` | `components/core_components.ex` |

If you need a helper that doesn't exist, add it to the right shared module and update this table.

## PubSub

All broadcasting and subscribing goes through `EyeInTheSky.Events` (`lib/eye_in_the_sky/events.ex`). **Never call `Phoenix.PubSub` directly.**

```elixir
# GOOD
EyeInTheSky.Events.agent_updated(agent)
EyeInTheSky.Events.subscribe_session(session_id)
```

Add a named function to Events for any new broadcast — don't hardcode topic strings anywhere else.

## UI Standards

### Icons

**Always use Heroicons** via `<.icon>`. Never use inline SVG.

```heex
<.icon name="hero-folder" class="w-4 h-4" />
<.icon name="hero-document-text" class="w-4 h-4" />
<.icon name="hero-chevron-right" class="w-4 h-4" />
```

### Full-Text Search

Use `EyeInTheSky.Search.PgSearch.search_for/2` for all full-text queries across sessions, tasks, and notes.

### User Settings & Themes

Preferences (theme, CodeMirror settings) are stored in the DB via Settings LiveView. Themes: `system`, `light`, `dark`, `dracula`, `tokyo-night`, Catppuccin variants. Applied via `phx:apply_theme` hook.

CodeMirror settings: tab size (2/4/8), font size (px), vim keybindings.

### Workflow States

| ID | Name        | Position | Color   |
|----|-------------|----------|---------|
| 1  | To Do       | 1        | #6B7280 |
| 2  | In Progress | 2        | #3B82F6 |
| 4  | In Review   | 3        | #F59E0B |
| 3  | Done        | 4        | #10B981 |

### Type Quirks

- Project PK is integer (`@primary_key {:id, :id, autogenerate: false}`). Task `project_id` uses `type: :string` for legacy compatibility.
- Agent `project_name` is a real DB column (not virtual).

### Schema Naming

- **`Agent`** (`lib/eye_in_the_sky/agents/agent.ex`) → `agents` table (identity/participant)
- **`Session`** (`lib/eye_in_the_sky/sessions/session.ex`) → `sessions` table (execution)

All agent identity operations go through `EyeInTheSky.Agents`. In LiveViews, `@session` is a `Session` struct with an `agent_id` FK to the agents table.

### Agent `last_activity_at`

ISO8601 text field, not a DateTime.
- Always pass ISO8601 strings when updating it
- Use `DateTime.from_iso8601/1` when comparing with Elixir datetimes
- Scheduling in `lib/eye_in_the_sky/scheduler/agent_status.ex` uses ISO8601 strings

Sessions can be sorted by `last_activity_at`, `created_at`, or `last_message_at` via `Sessions.list_sessions/2`.
