# CLAUDE.md

This file provides guidance to Claude Code when working with the Eye in the Sky web application.

## Project Overview

Phoenix/Elixir web app that provides a monitoring UI for Eye in the Sky.

This project uses Phoenix LiveView with Elixir. Primary languages: TypeScript, JavaScript, Elixir/HEEx, Go, Rust. Use Tailwind CSS for styling.

## Project Conventions

- The `tasks` table uses `created_at`, **not** `inserted_at`. Always verify timestamp field names against the schema before using them — using `inserted_at` will cause KeyErrors at runtime.

## Git Worktrees

**Always start any code change work in a worktree.** Never modify files directly in the main project directory. Create a worktree first, make changes there, then merge/PR back.

Worktrees live in `.claude/worktrees/` relative to the project root.

When using git worktrees, always verify you are editing files in the worktree directory, NOT the main project directory. Check `pwd` before making edits.

If deps are missing in the worktree, symlink them before compiling. Worktrees live at `.claude/worktrees/<name>/`, which is **3 levels deep** from the project root — use `../../../`:
```bash
cd .claude/worktrees/<name>
ln -s ../../../deps deps && ln -s ../../../_build _build
```

Do NOT use `../../` — that resolves to `.claude/`, not the project root, and the symlinks will be broken.

**Exception: when adding new Elixir modules or deps**, do NOT symlink `_build`. A symlinked `_build` causes stale module conflicts when the worktree introduces modules that don't exist in the main tree (compiled beams collide). For tasks that add new modules, run `mix deps.get` and `mix compile` directly in the worktree to get an isolated `_build`.

**CRITICAL: `rm` is aliased to `rm-trash` on this system.** It follows symlinks and trashes the target, not the symlink. To remove symlinks, always use `unlink`:
```bash
unlink _build && unlink deps
```

## Build & Run

```bash
mix deps.get
mix phx.server          # Start dev server on http://localhost:5001
PORT=5002 mix phx.server # Override port via PORT env var (range 5001-5020)
mix compile              # Compile only
```

Assets: `cd assets && npm install` for JS dependencies. Vite, Tailwind, and TypeScript compilation run as Phoenix watchers.

### Asset Pipeline: Vite Migration

The asset pipeline was migrated from esbuild to **Vite** for faster development and production builds:

```bash
# In assets/ directory
npm install                  # Install dependencies
npm run dev                  # Vite dev server (auto via phx.server)
npm run build               # Production build
```

Vite configuration lives in `assets/vite.config.ts`. The dev server runs on port 5173 by default (configurable via `VITE_PORT` env var). LiveSvelte SSR support and TypeScript compilation are integrated.

### Running a worktree server alongside main

Vite defaults to port 5173 with `strictPort: true` — a second instance will crash if the main server is already running. Use `VITE_PORT` to avoid the conflict:

```bash
VITE_PORT=5174 PORT=5002 mix phx.server
```

Pick any free port for `VITE_PORT`. The Vite dev server, LiveSvelte SSR host, and asset URL generation all read from it automatically.

## Playwright / Browser Testing

When using Playwright, start a dedicated server instance on a different port than the dev server with auth disabled:

```bash
PORT=5002 DISABLE_AUTH=true mix phx.server
```

Navigate Playwright to `http://localhost:5002`. This avoids interfering with the running dev server and bypasses the login wall.

## Development Workflow

**Before committing:** Always run `mix compile` to ensure the project compiles without errors. Only warnings are acceptable.

After completing code changes, always run `mix compile --warnings-as-errors` to verify clean compilation before committing.

**Before staging/committing:** Run `git status` and `git diff --staged` to check for pre-existing staged changes. Never assume a clean staging area — only commit the files relevant to the current task.

## Bug Fixes

When fixing bugs, grep the **entire codebase** for ALL occurrences of the problematic pattern before making any edits. List every file and line number, then fix all of them in a single pass. Don't fix just the first occurrence.

When a UI bug is reported, read the exact symptom carefully before investigating. Do not assume the category of bug. Don't investigate duplicate messages when the report is about dark mode CSS. Read the report literally, trace the code, then propose a fix.

## Session Status Lifecycle

Session status is driven by Claude Code hooks and explicit commands:

| Status | Set by | Meaning |
|--------|--------|---------|
| `working` | `UserPromptSubmit` hook | Claude is processing a message |
| `stopped` | `Stop` hook | Claude finished responding (resets to `working` on next message) |
| `waiting` | `SessionEnd` hook (`sdk-cli`) | Headless session ended; can be resumed |
| `completed` | `SessionEnd` hook (`cli`) or `/i-end-session` | Interactive session finished; or manually closed |
| `failed` | `SessionWorker` on non-zero exit | Process crashed |

`CLAUDE_CODE_ENTRYPOINT` distinguishes `cli` (interactive) from `sdk-cli` (headless/spawned).

## Entrypoint-Based Command Protocol

> **IMPORTANT: Check your entrypoint before dispatching ANY EITS command.**
> Run `echo $CLAUDE_CODE_ENTRYPOINT` at the start of every session.
> Using the wrong method silently fails or breaks session hierarchy.

**How you dispatch EITS commands depends on your `CLAUDE_CODE_ENTRYPOINT`:**

| Entrypoint | Mode | Use |
|------------|------|-----|
| `cli` | Interactive | `eits` CLI script |
| `sdk-cli` | Headless/spawned agent | `EITS-CMD:` directives in output |

**`sdk-cli` (headless/spawned agents) — use `EITS-CMD:` lines:**
```
EITS-CMD: task begin Fix broken import
EITS-CMD: task done 1234
EITS-CMD: task annotate 1234 What I did and why
EITS-CMD: dm --to <session_uuid> --message "done"
EITS-CMD: dm --to 1740 --message "done"
EITS-CMD: commit abc1234
```
These are intercepted by AgentWorker in-process — no HTTP round-trips. **Never use the `eits` bash script when running as `sdk-cli`.**

**DM targets support both UUID and numeric session ID** (as of commit ee6cacc). Pass either format to `dm --to`.

**`cli` (interactive sessions) — use `eits` script:**
```bash
eits tasks begin --title "Task name"   # replaces: create + start
eits tasks annotate <id> --body "..."
eits tasks update <id> --state 4
eits dm --to <session_uuid> --message "done"
```

**When spawning agents:** their `CLAUDE_CODE_ENTRYPOINT` will be `sdk-cli`. Write their instructions using `EITS-CMD:` directives, not `eits` CLI calls.

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

## Recent Features

### EITS-CMD Enhancements

- **Numeric Session ID Support**: DM targets now accept numeric session IDs in addition to UUIDs
- **Feedback Messages**: All EITS-CMD directives return feedback to the calling agent
- **Session Hierarchy**: Parent/child session tracking via `source_uuid` field

### Agent Definitions & Canvas System

- **Agent Definitions**: Database-backed tracking of global and project-level agent configurations (`.claude/agents`)
- **Canvas Overlay**: Floating session windows on a shared canvas with PubSub sync for real-time updates
- **Agent Display Names**: Custom display names from agent definitions shown in DM headers and session cards

### CodeMirror & Editor Improvements

- **CodeMirror Themes**: Integrated theme support (defaultHighlightStyle, syntax highlighting for markdown/JSON)
- **User Settings**: Tab size, font size, vim keybindings (persisted in Settings)
- **Code Editor**: CodeMirror replacing Highlight on project files and config pages

### Performance Optimizations

- **SessionQueries Extraction**: Refactored session queries from raw SQL to Ecto-based operations
- **Query Consolidation**: Eliminated redundant queries, optimized file scans (skip git dirs)
- **Search Performance**: PgSearch tsvector queries are O(log N) on indexed columns

## Architecture

- `lib/eye_in_the_sky/` - OTP application core (Repo, migrations, application.ex after rename from `eye_in_the_sky_web`)
- `lib/eye_in_the_sky_web/` - Contexts (Sessions, Tasks, Agents, Projects, Notes, Prompts, Commits, Canvases, AgentDefinitions)
- `lib/eye_in_the_sky_web_web/` - Web layer (LiveViews, components, router)
- `lib/eye_in_the_sky_web/search/pg_search.ex` - Full-text search using PostgreSQL tsvector/tsquery with ILIKE fallback (`EyeInTheSkyWeb.Search.PgSearch`)
- `lib/eye_in_the_sky_web/sessions/queries.ex` - SessionQueries module for Ecto-based session operations

## OTP App Rename

The OTP application name was renamed from `eye_in_the_sky_web` to `eye_in_the_sky` (commit 554da58). Key impacts:

- `EyeInTheSky.Repo` — Repo module is now under the `EyeInTheSky` namespace (was `EyeInTheSkyWeb.Repo`)
- Supervision tree references use `EyeInTheSky.Application`
- The `lib/eye_in_the_sky/` directory houses core OTP app files
- Context modules under `lib/eye_in_the_sky_web/` continue to use the `EyeInTheSkyWeb.*` namespace
- Web layer under `lib/eye_in_the_sky_web_web/` uses `EyeInTheSkyWebWeb.*` namespace

## Schema Conventions

### Timestamp Types

All tables use `:utc_datetime_usec` (microsecond precision UTC datetime). Migrations 20260321080000–20260321080200 converted all timestamp columns.

- Use `DateTime.utc_now()` when setting timestamps programmatically
- When comparing DB values against Elixir datetimes, use `DateTime.from_iso8601/1` to parse ISO8601 strings
- The `tasks` table uses `created_at`, **not** `inserted_at`

### UUID Columns

All UUID columns were converted from `varchar` to native PostgreSQL `uuid` type (migration 20260322011755). A `source_uuid` field was also added.

- Ecto uses `Ecto.UUID` codec directly for native `uuid` columns — no manual encoding/decoding needed
- Queries using UUID values pass them as plain strings; Ecto handles the codec
- The `source_uuid` field tracks the originating session/agent UUID for cross-referencing

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

### User Settings & Themes

User preferences (theme, CodeMirror settings) are stored in the database and persisted via Settings LiveView. Available themes:

- `system` - Default, respects OS dark/light preference
- `light` - Explicit light mode
- `dark` - Explicit dark mode
- `dracula` - Dracula theme
- `tokyo-night` - Tokyo Night theme
- Catppuccin themes (via `@catppuccin/daisyui` plugin)

CodeMirror user settings:
- **Tab Size**: 2, 4, or 8 spaces
- **Font Size**: Configurable in pixels (default 12px)
- **Vim Keybindings**: Toggle on/off

Settings are applied via `phx:apply_theme` hook and persisted in the `settings` table.

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
