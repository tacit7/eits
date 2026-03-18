# CLAUDE.md

This file provides guidance to Claude Code when working with the Eye in the Sky web application.

## Project Overview

Phoenix/Elixir web app that provides a monitoring UI for Eye in the Sky.

This project uses Phoenix LiveView with Elixir. Primary languages: TypeScript, JavaScript, Elixir/HEEx, Go, Rust. Use Tailwind CSS for styling.

## Git Worktrees

When working in git worktrees, always compile from the main project directory or symlink deps/build directories first. Never attempt to compile directly in a worktree without verifying deps are available.

When using git worktrees, always verify you are editing files in the worktree directory, NOT the main project directory. Check `pwd` before making edits.

## Build & Run

```bash
mix deps.get
mix phx.server          # Start dev server on http://localhost:5000
PORT=5002 mix phx.server # Override port via PORT env var (range 5000-5020)
mix compile              # Compile only
```

Assets: `cd assets && npm install` for JS dependencies. Esbuild and Tailwind run as Phoenix watchers.

## Development Workflow

**Before committing:** Always run `mix compile` to ensure the project compiles without errors. Only warnings are acceptable.

After completing code changes, always run `mix compile --warnings-as-errors` to verify clean compilation before committing.

## Bug Fixes

When fixing bugs, search the entire file for ALL occurrences of the problematic pattern before committing. Don't fix just the first occurrence.

## Session Status Lifecycle

Session status is driven by Claude Code hooks and explicit commands:

| Status | Set by | Meaning |
|--------|--------|---------|
| `working` | `UserPromptSubmit` hook | Claude is processing a message |
| `stopped` | `Stop` hook | Claude finished responding (resets to `working` on next message) |
| `waiting` | `SessionEnd` hook (`cli_sdk`) | Interactive session ended; can be resumed |
| `completed` | `SessionEnd` hook (`cli`) or `/i-end-session` | Spawned agent finished; or manually closed |
| `failed` | `SessionWorker` on non-zero exit | Process crashed |

`CLAUDE_CODE_ENTRYPOINT` distinguishes `cli` (spawned/print mode) from `cli_sdk` (interactive).

**Task workflow — use `begin` to create and start in one shot:**
```bash
eits tasks begin --title "Task name"   # replaces: create + start
eits tasks annotate <id> --body "..."
eits tasks update <id> --state 4
```

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

PostgreSQL database `eits_dev` on localhost. Configured in `config/dev.exs`. **This app owns the schema** — Go is no longer involved. Schema changes are made via Ecto migrations (`mix ecto.gen.migration` / `mix ecto.migrate`).

## Architecture

- `lib/eye_in_the_sky_web/` - Contexts (Sessions, Tasks, Agents, Projects, Notes, Prompts, Commits)
- `lib/eye_in_the_sky_web_web/` - Web layer (LiveViews, components, router)
- `lib/eye_in_the_sky_web/search/pg_search.ex` - Full-text search using PostgreSQL tsvector/tsquery with ILIKE fallback (`EyeInTheSkyWeb.Search.PgSearch`)

## PubSub

All PubSub broadcasting and subscribing goes through `EyeInTheSkyWeb.Events` (`lib/eye_in_the_sky_web/events.ex`). **Never call `Phoenix.PubSub.broadcast` or `Phoenix.PubSub.subscribe` directly** — use the named functions in Events.

```elixir
# GOOD
EyeInTheSkyWeb.Events.agent_updated(agent)
EyeInTheSkyWeb.Events.subscribe_session(session_id)

# BAD
Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "agents", {:agent_updated, agent})
Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session_id}")
```

Events owns all topic strings. If you need a new broadcast, add a named function to Events — don't hardcode a topic anywhere else. `EyeInTheSkyWebWeb.Helpers.PubSubHelpers` is a thin compatibility wrapper that delegates to Events; prefer calling Events directly in new code.

## Documentation

Project docs live in `docs/`. Key references:

- [docs/SECURITY.md](docs/SECURITY.md) — Security architecture: auth, session handling, rate limiting, secrets, transport security
- [docs/REST_API.md](docs/REST_API.md) — Full API endpoint reference
- [docs/SETUP.md](docs/SETUP.md) — Project setup guide
- [docs/CODE_GUIDELINES.md](docs/CODE_GUIDELINES.md) — Coding standards
- [docs/EITS_CLI.md](docs/EITS_CLI.md) — CLI reference
- [docs/EITS_HOOKS.md](docs/EITS_HOOKS.md) — Hook system
- [docs/DM_FEATURES.md](docs/DM_FEATURES.md) — DM/messaging features
- [docs/SESSION_MANAGER.md](docs/SESSION_MANAGER.md) — Session lifecycle
- [docs/WORKERS.md](docs/WORKERS.md) — Background workers
- [docs/KANBAN.md](docs/KANBAN.md) — Kanban board
- [docs/COMMAND_PALETTE.md](docs/COMMAND_PALETTE.md) — Command palette
- [docs/chat-mention-workflow.md](docs/chat-mention-workflow.md) — Chat @mention system
- [docs/claude-cli-flags.md](docs/claude-cli-flags.md) — Claude CLI flag reference
- [docs/CONTEXT_WINDOW.md](docs/CONTEXT_WINDOW.md) — Context window handling
- [docs/SEARCH.md](docs/SEARCH.md) — Full-text search: PgSearch implementation, prefix-aware tsquery, callers
- [docs/CODEX_SDK.md](docs/CODEX_SDK.md) — Codex SDK: session lifecycle, JSONL events, resume flow, env vars
- [docs/CHAT.md](docs/CHAT.md) — Chat system: channels, routing protocol, @mentions, cross-project membership
- [docs/EVENTS.md](docs/EVENTS.md) — PubSub Events module: all topics, payload shapes, subscribe helpers, how to add new events

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

### Full-Text Search

`lib/eye_in_the_sky_web/search/pg_search.ex` (`EyeInTheSkyWeb.Search.PgSearch`) wraps PostgreSQL `tsvector/tsquery` full-text search with an ILIKE fallback. Use `PgSearch.search_for/2` for all full-text queries across sessions, tasks, and notes.

**Helper Function: `PgSearch.fts_name_description_match/1`**

Extracts reusable tsvector query fragments for common search patterns across sessions, tasks, and notes. This helper:
- Builds PostgreSQL `@@` operator queries on indexed columns
- Returns parameterized tsvector expressions for use in composed queries
- Falls back to ILIKE for partial matching when tsquery doesn't match
- Used in Sessions, Tasks, and Notes contexts for consistent search behavior
- Performance: tsvector queries are O(log N) on indexed columns vs O(N) for ILIKE

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

### Agent `last_activity_at` Schema

**Migration History:**
- Previous: DateTime field (Elixir datetime)
- Current: ISO8601 text field (standardized string format)
- Migration: `20260309000001_change_agent_last_activity_at_to_text.exs`

**Impact:**
- Agent status scheduling in `lib/eye_in_the_sky_web/scheduler/agent_status.ex` now uses ISO8601 strings
- Queries comparing timestamps must use string comparison or convert to datetime
- Use `DateTime.from_iso8601/1` when comparing with Elixir datetime values
- Always pass ISO8601 strings when updating `last_activity_at` on agents

**Sessions `last_activity_at` Ordering:**
- Sessions can be sorted by `last_activity_at`, `created_at`, or `last_message_at`
- Use `Sessions.list_sessions/2` with `:last_activity_at`, `:created_at`, or `:last_message_at` sort options
- Filtering works with ISO8601 string values; comparisons use standard string ordering
