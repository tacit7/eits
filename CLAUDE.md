# CLAUDE.md

This file provides guidance to Claude Code when working with the Eye in the Sky web application.

## Project Overview

Phoenix/Elixir web app that provides a monitoring UI for Eye in the Sky. MCP server is Anubis (HTTP MCP), not Go.

## Build & Run

```bash
mix deps.get
mix phx.server          # Start dev server on http://localhost:5001
mix compile              # Compile only
```

Assets: `cd assets && npm install` for JS dependencies. Esbuild and Tailwind run as Phoenix watchers.

## Development Workflow

**Before committing:** Always run `mix compile` to ensure the project compiles without errors. Only warnings are acceptable.

## REST API

JSON API at `/api/v1` for Claude Code hooks and external integrations. See [docs/REST_API.md](docs/REST_API.md) for full endpoint reference, request/response formats, and PubSub broadcast details.

## Claude CLI & API Keys

This app spawns Claude CLI processes to run agents. API key configuration:

- **Environment-based**: Claude CLI uses `ANTHROPIC_API_KEY` from the system environment or `~/.config/claude/config.toml`
- **No DB storage**: API keys are NOT stored in the database
- **Pass-through**: The CLI module passes through all system environment variables to spawned Claude processes

Common error when API key has insufficient credits:
```json
{"type":"assistant","message":{"content":[{"type":"text","text":"Credit balance is too low"}]},"error":"billing_error"}
```

Exit status will be 1 (error) instead of 0 (success).

## Database

PostgreSQL database `eits_dev` on localhost. Configured in `config/dev.exs`. **This app owns the schema** — Go is no longer involved. Schema changes are made via direct psql (no Ecto migrations).

## Architecture

- `lib/eye_in_the_sky_web/` - Contexts (Sessions, Tasks, Agents, Projects, Notes, Prompts, Commits)
- `lib/eye_in_the_sky_web_web/` - Web layer (LiveViews, components, router)
- `lib/eye_in_the_sky_web/search/fts5.ex` - Full-text search using PostgreSQL tsvector/tsquery with ILIKE fallback (module name is legacy from SQLite era)

## UI Standards

### Icons

**Always use Heroicons** via the Phoenix `<.icon>` component. Never use inline SVG paths.

```heex
<!-- GOOD -->
<.icon name="hero-folder" class="w-4 h-4" />
<.icon name="hero-document-text" class="w-4 h-4" />
<.icon name="hero-chevron-right" class="w-4 h-4" />

<!-- BAD -->
<svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="..." />
</svg>
```

Common icons:
- `hero-folder` - Directories
- `hero-document-text` - Files
- `hero-chevron-right` - Expand/collapse indicators
- `hero-x-mark` - Close buttons
- `hero-pencil-square` - Edit buttons

### NATS Processing (Currently Disabled)

NATS message processing is **currently disabled** to prevent duplicate messages. The following are disabled:
- `JetStreamConsumer` - V1/V2 channel messages, DM handling all disabled
- DM LiveView - NATS message handler disabled
- SessionWorker - Result message saving disabled (only assistant messages saved)

Original code is kept as comments for future re-enablement when proper deduplication is implemented.

### Full-Text Search

`lib/eye_in_the_sky_web/search/fts5.ex` wraps PostgreSQL `tsvector/tsquery` full-text search with an ILIKE fallback. The module name is a legacy artifact from the SQLite era — it is not FTS5. Use `FTS5.search_for/2` for all full-text queries across sessions, tasks, and notes.

### Workflow States

The `workflow_states` table defines kanban columns. Current states:

| ID | Name        | Position | Color   |
|----|-------------|----------|---------|
| 1  | To Do       | 1        | #6B7280 |
| 2  | In Progress | 2        | #3B82F6 |
| 4  | In Review   | 3        | #F59E0B |
| 3  | Done        | 4        | #10B981 |

### Type Quirks

- Project PK is integer (`@primary_key {:id, :id, autogenerate: false}`). Task `project_id` uses `type: :string` in the Ecto association for legacy compatibility.
- Agent `project_name` is a real DB column (not virtual).

### Schema Naming

Two schemas map to different DB tables:

- **`Agent` schema** (`lib/eye_in_the_sky_web/agents/agent.ex`) → **`agents` DB table** (agent identity/participant)
- **`Session` schema** (`lib/eye_in_the_sky_web/sessions/session.ex`) → **`sessions` DB table** (execution session)

The old `ChatAgent` schema and `ChatAgents` context have been removed. All agent identity operations go through `EyeInTheSkyWeb.Agents`.

In LiveViews and components:
- `@session` typically refers to a `Session` struct (from sessions table)
- Sessions have an `agent_id` foreign key pointing to the agents table
- The `Agents` context handles agent CRUD; the `Sessions` context handles session-specific logic like `format_model_info/1`
