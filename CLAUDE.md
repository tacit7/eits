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

## EITS Command Protocol

All agents — interactive (`cli`) and headless (`sdk-cli`) — use the `eits` CLI script directly. EITS-CMD directives are deprecated.

```bash
eits tasks begin --title "Task name"   # create + start in one shot
eits tasks annotate <id> --body "..."
eits tasks update <id> --state 4
eits tasks complete <id> --message "Summary"
eits dm --to <session_uuid> --message "done"
eits dm --to 1740 --message "done"     # numeric session ID also works
eits commits create --hash <hash>
```

**DM targets support both UUID and numeric session ID.** Pass either format to `dm --to`.

## REST API

JSON API at `/api/v1` for Claude Code hooks and external integrations. See [docs/REST_API.md](docs/REST_API.md) for full endpoint reference, request/response formats, and PubSub broadcast details.

## Claude CLI & API Keys

This app spawns Claude CLI processes to run agents. API key configuration:

- **Max plan OAuth**: Spawned Claude processes authenticate via Max plan OAuth credentials stored in the macOS keychain — no API key needed.
- **ANTHROPIC_API_KEY is blocked**: `build_env` in `claude/cli.ex` explicitly strips `ANTHROPIC_API_KEY` from the spawned process environment. This prevents a leaked API key in the server env from overriding Max plan OAuth and causing "Credit balance is too low" billing errors.
- **No DB storage**: API keys are NOT stored in the database.

Common error when API key has insufficient credits:
```json
{"type":"assistant","message":{"content":[{"type":"text","text":"Credit balance is too low"}]},"error":"billing_error"}
```

Exit status will be 1 (error) instead of 0 (success).

## Database

PostgreSQL database `eits_dev` on localhost. Configured in `config/dev.exs`. **This app owns the schema** — Go is no longer involved. Schema changes are made via Ecto migrations (`mix ecto.gen.migration` / `mix ecto.migrate`).

## Architecture

See `lib/CLAUDE.md` for full architecture, schema conventions, PubSub rules, and UI standards.

## Documentation

See `docs/CLAUDE.md` for the full documentation index.
