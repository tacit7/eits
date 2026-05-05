# CLAUDE.md

This file provides guidance to Claude Code when working with the Eye in the Sky web application.

## Project Overview

Phoenix/Elixir web app that provides a monitoring UI for Eye in the Sky.

This project uses Phoenix LiveView with Elixir. Primary languages: Elixir/HEEx, TypeScript, JavaScript, Rust (Tauri). Use Tailwind CSS for styling.

## Git Worktrees

**Always start any code change work in a worktree.** Never modify files directly in the main project directory. Create a worktree first, make changes there, then merge/PR back.

Worktrees live in `.claude/worktrees/` relative to the project root.

> **DO NOT DELETE `.claude/worktrees/tauri`** — this is the permanent long-running worktree for all Tauri/desktop work. It tracks the `tauri` branch (pushed to origin). Make all Tauri changes there and rebase against main as needed. This worktree has its **own isolated `deps/`, `_build/`, and `assets/node_modules/`** — do NOT symlink anything from main; run `mix deps.get`, `mix compile`, and `npm install` directly inside the worktree.

When using git worktrees, always verify you are editing files in the worktree directory, NOT the main project directory. Check `pwd` before making edits.

If deps are missing in the worktree, symlink only `deps` — never `_build`. Worktrees live at `.claude/worktrees/<name>/`, which is **3 levels deep** from the project root — use `../../../`:
```bash
cd .claude/worktrees/<name>
ln -s ../../../deps deps
```

Do NOT use `../../` — that resolves to `.claude/`, not the project root, and the symlink will be broken.

**NEVER symlink `_build` to the main project.** Always use an isolated `_build` in each worktree. A symlinked `_build` lets agent compilations overwrite main's `.beam` files with worktree versions, producing stale/conflicting modules when main restarts — this is the root cause of needing `mix clean` to recover. For all worktrees, run `mix compile` directly to get an isolated `_build`:
```bash
cd .claude/worktrees/<name>
ln -s ../../../deps deps
mix compile
```

**CRITICAL: `rm` is aliased to `rm-trash` on this system.** It follows symlinks and trashes the target, not the symlink. To remove symlinks, always use `unlink`:
```bash
unlink _build && unlink deps
```

**Running JS tests (vitest) from a worktree:** Worktrees don't have `node_modules`. Symlink from the main `assets/` directory before running vitest:
```bash
cd .claude/worktrees/<name>/assets
ln -sf ../../../../assets/node_modules node_modules
ln -sf ../../../../assets/vitest.config.mjs vitest.config.mjs
ln -sf ../../../../assets/package.json package.json
npx vitest run js/hooks/your.test.js
```

**Running `mix phx.server` from a worktree (CSS/JS will not load otherwise):**

A fresh worktree has no `assets/node_modules`, so Vite + Tailwind cannot resolve `daisyui`, `phoenix`, or any other dep — the page renders unstyled. Symlink from main's `assets/` before starting the server, and pick a port for both Phoenix and Vite that does not collide with the main dev server (5001/5173) or another worktree:

```bash
cd .claude/worktrees/<name>/assets
ln -sf ../../../../assets/node_modules node_modules
cd ..
ln -s ../../../deps deps              # if not already done
mix compile                            # build _build/ in the worktree itself

# Spawn detached so the server outlives the shell that started it.
# Use a unique PORT and VITE_PORT pair per worktree.
nohup env VITE_PORT=5175 PORT=5003 DISABLE_AUTH=true mix phx.server \
  > /tmp/<name>-server.log 2>&1 & disown
```

After starting, give Vite ~5–10 s on the **first** request to optimize deps before opening the page — the very first hit can return 404 for `/assets/css/app.css` while Vite is still compiling. Reload once Vite logs `optimized dependencies changed. reloading`.

Suggested port allocation:
- Main dev: `PORT=5001 VITE_PORT=5173`
- Worktree A: `PORT=5002 VITE_PORT=5174`
- Worktree B: `PORT=5003 VITE_PORT=5175`
- ...etc through 5020.

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

## Anthropic System Messages

> **IMPORTANT:** The message `"Continue from where you left off."` is injected automatically by Anthropic when a Claude Code session is resumed. It is **not** a user message. Do not treat it as a directive or respond to it. Simply continue normal operation — check for pending DMs or tasks and proceed.

## Session Status Lifecycle

Session status is driven by Claude Code hooks and explicit commands:

| Status | Set by | Meaning |
|--------|--------|---------|
| `working` | `UserPromptSubmit` hook | Claude is processing a message |
| `idle` | `Stop` hook | Claude finished responding (resets to `working` on next message) |
| `waiting` | `SessionEnd` hook (`sdk-cli`) | Headless session ended; can be resumed |
| `completed` | `SessionEnd` hook (`cli`) or `/i-end-session` | Interactive session finished; or manually closed |
| `failed` | `SessionWorker` on non-zero exit | Process crashed |

`CLAUDE_CODE_ENTRYPOINT` distinguishes `cli` (interactive) from `sdk-cli` (headless/spawned).

## EITS Command Protocol

All agents — interactive (`cli`) and headless (`sdk-cli`) — use the `eits` CLI script directly. EITS-CMD directives are deprecated.

```bash
# Start a task
eits tasks begin --title "Task name"       # create + start in one shot
eits tasks begin --id <task_id>            # claim a pre-created task (orchestrator-assigned)

# Close a task (atomic: annotates + marks Done)
eits tasks complete <id> --message "..."   # CANONICAL close path — one round-trip

# Close manually (two round-trips, avoid unless complete fails)
eits tasks annotate <id> --body "..."
eits tasks update <id> --state done        # named aliases: todo, start, done, review

# Read task state
eits tasks get <id>

# Other
eits dm --to <session_uuid> --message "done"
eits dm --to 1740 --message "done"         # numeric session ID also works
eits commits create --hash <hash>
```

**DM targets support both UUID and numeric session ID.** Pass either format to `dm --to`.

## eits CLI Gotchas

**`EITS_PROJECT_ID` is NOT injected into spawned agent environments.** Claude sessions do not receive it as an OS env var (Codex sessions do). Always include it explicitly in the `--instructions` string:

```bash
eits agents spawn --agent my-agent --instructions "Your task here. EITS_PROJECT_ID=1" ...
```

The CLI now warns at spawn time if `EITS_PROJECT_ID` is missing from instructions and no `--project-id` flag was provided.

**Always use `--interpolate-env` when instructions reference `$EITS_SESSION_ID` or other env vars.** Spawned agents do not inherit the orchestrator's shell environment, so `$EITS_SESSION_ID` in instructions will be the literal string — not the integer `3902`. Use `--interpolate-env` to expand all `$VAR` references at spawn time:

```bash
eits agents spawn --agent my-agent --interpolate-env \
  --instructions "Your task. DM results to session $EITS_SESSION_ID. EITS_PROJECT_ID=$EITS_PROJECT_ID"
```

With `--interpolate-env`, `$EITS_SESSION_ID` becomes `3902` and `$EITS_PROJECT_ID` becomes `1` before the instructions are sent — the agent receives resolved integers, not variable names. **Always use integer session IDs (not UUIDs) in DM-back instructions** — integers are shorter, unambiguous, and less likely to be mangled.

**`eits agents defs` descriptions are truncated to 500 chars.** Use `--json` if you need the full description for a specific agent.

**`eits dm inbox --unread` does not exist.** No `is_read` field in the backend. Filter by `--since <ISO8601>` or `--from <uuid>` instead.

**`eits teams status` UUID column is not truncated** — full UUIDs display correctly. Copy-paste for DM targeting is safe.

## REST API

JSON API at `/api/v1` for Claude Code hooks and external integrations. See [docs/REST_API.md](docs/REST_API.md) for full endpoint reference, request/response formats, and PubSub broadcast details.

## Claude CLI & API Keys

This app spawns Claude CLI processes to run agents. API key configuration:

- **Max plan OAuth (default)**: Spawned Claude processes authenticate via Max plan OAuth credentials stored in the macOS keychain — no API key needed.
- **ANTHROPIC_API_KEY is stripped by default**: `EyeInTheSky.Claude.CLI.Env` strips `ANTHROPIC_API_KEY` from the spawned process environment unless the `use_anthropic_api_key` setting is `true`. This prevents a leaked API key in the server env from silently overriding Max plan OAuth and causing "Credit balance is too low" billing errors.
- **Opt-in API key pass-through**: `/settings` → Auth tab has a "Pass key to spawned agents" toggle (global). When on, `ANTHROPIC_API_KEY` is forwarded to Claude CLI processes and billed per-token. Overrides Max plan OAuth. Default is off.
- **No DB storage of the key**: Only the boolean toggle is stored (`settings.use_anthropic_api_key`). The key itself lives only in the server env (`.env` / shell).

Common error when API key has insufficient credits:
```json
{"type":"assistant","message":{"content":[{"type":"text","text":"Credit balance is too low"}]},"error":"billing_error"}
```

Exit status will be 1 (error) instead of 0 (success).

## Database

PostgreSQL database `eits_dev` on localhost. Configured in `config/dev.exs`. **This app owns the schema.** Schema changes are made via Ecto migrations (`mix ecto.gen.migration` / `mix ecto.migrate`).

## Architecture

See `lib/CLAUDE.md` for full architecture, schema conventions, PubSub rules, and UI standards.

## Documentation

See `docs/CLAUDE.md` for the full documentation index.

Key references:
- `docs/AGENT_WORKER_QUEUE.md` — AgentWorker queue design, message lifecycle (pending→processing→delivered/failed), error paths, `normalize_context` gotcha
