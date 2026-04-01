# CLAUDE.md

This file provides guidance to Claude Code when working with the Eye in the Sky web application.

## Project Overview

Phoenix/Elixir web app that provides a monitoring UI for Eye in the Sky.

This project uses Phoenix LiveView with Elixir. Primary languages: TypeScript, JavaScript, Elixir/HEEx, Go, Rust. Use Tailwind CSS for styling.

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

Asset pipeline uses **Vite** (`assets/vite.config.mjs`). Dev server runs on port 5173 (override with `VITE_PORT`). When running a worktree server alongside main, use a different port to avoid conflicts:

```bash
VITE_PORT=5174 PORT=5002 mix phx.server
```

## Playwright / Browser Testing

When using Playwright, start a dedicated server instance on a different port than the dev server with auth disabled:

```bash
PORT=5002 DISABLE_AUTH=true mix phx.server
```

Navigate Playwright to `http://localhost:5002`. This avoids interfering with the running dev server and bypasses the login wall.

## Development Workflow

**Before committing:** Run `mix compile --warnings-as-errors`. Only warnings are acceptable, no errors.

**Before staging/committing:** Run `git status` and `git diff --staged` to check for pre-existing staged changes. Never assume a clean staging area — only commit the files relevant to the current task.

## Bug Fixes

When fixing bugs, grep the **entire codebase** for ALL occurrences of the problematic pattern before making any edits. List every file and line number, then fix all of them in a single pass. Don't fix just the first occurrence.

When a UI bug is reported, read the exact symptom carefully before investigating. Do not assume the category of bug. Read the report literally, trace the code, then propose a fix.

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

## Architecture

- `lib/eye_in_the_sky/` - OTP core: Repo, contexts (Sessions, Tasks, Agents, Projects, Notes, Prompts, Commits, Canvases, AgentDefinitions), search, scheduler
- `lib/eye_in_the_sky_web/` - Web layer entry point (endpoint, router, plugs)
- `lib/eye_in_the_sky_web_web/` - LiveViews, components, controllers
- `lib/eye_in_the_sky/search/pg_search.ex` - Full-text search using PostgreSQL tsvector/tsquery with ILIKE fallback (`EyeInTheSky.Search.PgSearch`)
- `lib/eye_in_the_sky/sessions/queries.ex` - SessionQueries module for Ecto-based session operations

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

All PubSub broadcasting and subscribing goes through `EyeInTheSky.Events` (`lib/eye_in_the_sky/events.ex`). **Never call `Phoenix.PubSub.broadcast` or `Phoenix.PubSub.subscribe` directly** — use the named functions in Events.

```elixir
# GOOD
EyeInTheSky.Events.agent_updated(agent)
EyeInTheSky.Events.subscribe_session(session_id)

# BAD
Phoenix.PubSub.broadcast(EyeInTheSky.PubSub, "agents", {:agent_updated, agent})
Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "session:#{session_id}")
```

Events owns all topic strings. If you need a new broadcast, add a named function to Events — don't hardcode a topic anywhere else.

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

`lib/eye_in_the_sky/search/pg_search.ex` (`EyeInTheSky.Search.PgSearch`) wraps PostgreSQL `tsvector/tsquery` full-text search with an ILIKE fallback. Use `PgSearch.search_for/2` for all full-text queries across sessions, tasks, and notes.

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

- **`Agent` schema** (`lib/eye_in_the_sky/agents/agent.ex`) → **`agents` DB table** (agent identity/participant)
- **`Session` schema** (`lib/eye_in_the_sky/sessions/session.ex`) → **`sessions` DB table** (execution session)

All agent identity operations go through `EyeInTheSky.Agents`.

In LiveViews and components:
- `@session` typically refers to a `Session` struct (from sessions table)
- Sessions have an `agent_id` foreign key pointing to the agents table
- The `Agents` context handles agent CRUD; the `Sessions` context handles session-specific logic like `format_model_info/1`

### Agent `last_activity_at` Schema

`last_activity_at` is an ISO8601 text field, not a DateTime.
- Always pass ISO8601 strings when updating it
- Use `DateTime.from_iso8601/1` when comparing with Elixir datetime values
- Agent status scheduling in `lib/eye_in_the_sky/scheduler/agent_status.ex` uses ISO8601 strings

**Sessions `last_activity_at` Ordering:**
- Sessions can be sorted by `last_activity_at`, `created_at`, or `last_message_at`
- Use `Sessions.list_sessions/2` with `:last_activity_at`, `:created_at`, or `:last_message_at` sort options
- Filtering works with ISO8601 string values; comparisons use standard string ordering
