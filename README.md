# Eye in the Sky — Web UI

A Phoenix/LiveView monitoring interface for Claude Code agent sessions. Tracks sessions, tasks, notes, commits, and DMs in real time. Built to run alongside the Eye in the Sky Go core (MCP server).

## Overview

This app is a read-heavy consumer of the shared SQLite database owned by the Eye in the Sky Go core. It does **not** manage the schema — all schema changes are handled by the Go core. The web UI subscribes to PubSub events and renders live updates as agents work.

**Features:**
- Real-time session and agent monitoring
- Task board with kanban workflow states
- Agent DM chat with @mention support
- Notes and commit tracking per session
- Full-text search across sessions, tasks, and notes (FTS5)
- REST API for Claude Code hook integration
- MCP server with tools for agent self-reporting

## Prerequisites

| Dependency | Version | Notes |
|-----------|---------|-------|
| Elixir | 1.15+ | |
| Erlang/OTP | 26+ | |
| Node.js | 18+ | Asset building |
| Eye in the Sky core | latest | Owns the SQLite schema at `~/.config/eye-in-the-sky/eits.db` |
| NATS | optional | Real-time message streaming |

Install Elixir via [asdf](https://asdf-vm.com/) or Homebrew:

```bash
brew install elixir
```

## Installation

### 1. Clone

```bash
git clone https://github.com/tacit7/eits-web.git
cd eits-web
```

### 2. Install dependencies

```bash
mix deps.get
cd assets && npm install && cd ..
```

### 3. Configure database path

Defaults to `~/.config/eye-in-the-sky/eits.db`. Update `config/dev.exs` if your Go core uses a different path:

```elixir
config :eye_in_the_sky_web, EyeInTheSkyWeb.Repo,
  database: Path.expand("~/.config/eye-in-the-sky/eits.db"),
```

### 4. Build assets

```bash
mix assets.build
```

### 5. Start the server

```bash
mix phx.server
```

Runs at [http://localhost:4000](http://localhost:4000).

---

## Claude Code Hook Integration

The `scripts/` directory contains a full hook suite that wires Claude Code session lifecycle events into Eye in the Sky.

### Quick install

```bash
./scripts/install.sh
```

Copies all `eits-*.sh` hooks to `~/.claude/hooks/` and makes them executable. Then merge `scripts/settings.json` into `~/.claude/settings.json` to activate the hooks.

### Manual install

```bash
cp scripts/eits-*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/eits-*.sh

# Merge settings (requires jq)
jq -s '.[0] * .[1]' ~/.claude/settings.json scripts/settings.json > /tmp/merged.json
mv /tmp/merged.json ~/.claude/settings.json
```

### Hook reference

| Hook event | Script | What it does |
|-----------|--------|-------------|
| `SessionStart (startup/resume)` | `eits-session-init.sh` | Registers session in DB, injects EITS context into Claude, writes env vars |
| `SessionStart (startup/resume)` | `eits-agent-working.sh` | Sets agent status to `working` |
| `SessionStart (compact)` | `eits-session-compact.sh` | Ends old session as `compacted`, lets init create a fresh one |
| `SessionEnd` | `eits-session-end.sh` | Marks session `completed`, sets `ended_at` |
| `Stop` | `eits-session-stop.sh` | Sets session status to `idle` on Ctrl+C |
| `PreToolUse` | `eits-pre-tool-use.sh` | Logs tool call to `actions` table |
| `PostToolUse` | `eits-post-tool-use.sh` | Logs tool result/error to `actions` table |

### Environment variables set by hooks

After `eits-session-init.sh` runs, these are available to all hooks and MCP tools in the session:

| Variable | Description |
|----------|-------------|
| `EITS_SESSION_ID` | Claude Code session UUID |
| `EITS_AGENT_ID` | EITS agent UUID |
| `EITS_PROJECT_ID` | EITS project integer ID |

### Utility scripts

**`scripts/nats/`** — manually publish NATS events for testing:

| Script | Purpose |
|--------|---------|
| `publish-session-start.sh` | Simulate session start |
| `publish-session-end.sh` | Simulate session end |
| `publish-session-stop.sh` | Simulate Ctrl+C stop |
| `publish-session-compact.sh` | Simulate compaction |
| `publish-tool-pre.sh` | Simulate PreToolUse |
| `publish-tool-post.sh` | Simulate PostToolUse |
| `publish-agent-status.sh` | Publish agent status change |
| `publish-domain-event.sh` | Publish generic domain event |

**`scripts/sql/`** — direct DB operations:

| Script | Purpose |
|--------|---------|
| `update-agent-status.sh` | Set agent status directly |
| `update-session-status.sh` | Set session status directly |
| `update-session-to-working.sh` | Reset session status to `working` |
| `check-active-todo.sh` | List active tasks from DB |

**Other scripts:**

| Script | Purpose |
|--------|---------|
| `scripts/spawn-agent.sh` | Spawn a new Claude Code agent |
| `scripts/notify.sh` | Send macOS notification |
| `scripts/build.sh` | Build NATS demo binary |

---

## Skills (Slash Commands)

Skills extend Claude Code with reusable workflows, invoked via `/skill-name` inside a Claude Code session.

### Project-level skills (`.claude/skills/`)

Scoped to this project:

| Skill | Command | Description |
|-------|---------|-------------|
| `check-docs` | `/check-docs <topic>` | Looks up a topic in the global docs project at `~/projects/docs` |
| `skill-builder` | `/skill-builder [name]` | Interactive guide for creating new Claude Code skills and registering them in EITS |

### Global EITS skills

Install these globally to `~/.claude/skills/` for use across any project:

| Skill | Command | Description |
|-------|---------|-------------|
| `eits-init` | `/eits-init` | **Required at session start.** Registers session with EITS, creates session ticket, sets up tracking. |
| `eits-chat` | *(auto)* | Handles `eits-chat:` messages from the web UI. Parses channel/message, sends response via `i-chat-send`. |
| `doc-search` | `/doc-search <query>` | Full-text search across emdash-indexed documentation libraries. |
| `i-compact` | `/i-compact` | Handle context compaction: ends old session, starts fresh one. |
| `i-end-session` | `/i-end-session` | Gracefully end the current EITS session. |
| `gitea` | `/gitea` | Gitea PR and repo workflow. |

### Registering a skill in EITS (DM autocomplete)

```bash
curl -s -X POST http://localhost:4000/api/v1/prompts \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My Skill",
    "slug": "my-skill",
    "description": "What this skill does",
    "prompt_text": "<full SKILL.md body>"
  }'
```

Registered skills appear immediately in DM `/` autocomplete.

---

## REST API

Base URL: `http://localhost:4000/api/v1`

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/sessions` | Register a Claude Code session |
| `PATCH` | `/sessions/:uuid` | Update session status |
| `POST` | `/commits` | Track git commits |
| `POST` | `/notes` | Add a note to a session/agent/task |
| `POST` | `/session-context` | Save/update session context markdown |
| `POST` | `/prompts` | Register a skill as an EITS prompt |

Full reference: [docs/REST_API.md](docs/REST_API.md)

---

## Development

```bash
mix phx.server          # Dev server with live reload
iex -S mix phx.server   # Inside IEx
mix compile             # Compile check
mix test                # Run tests
mix precommit           # Full gate: compile, format, unused deps, tests
```

### Project layout

```
lib/
  eye_in_the_sky_web/         # Contexts: Sessions, Agents, Tasks, Notes, Prompts, Commits
  eye_in_the_sky_web_web/     # LiveViews, components, router, REST controllers
scripts/
  eits-*.sh                   # Claude Code hook scripts
  install.sh                  # Hook installer
  settings.json               # Settings template for hooks config
  nats/                       # NATS publish/utility scripts
  sql/                        # SQL utility scripts
.claude/
  skills/                     # Project-level slash commands
docs/
  REST_API.md                 # REST API reference
```

### Database

**No migrations.** Schema is owned by the Go core. `priv/repo/migrations/` must stay empty.

---

## Tech Stack

- [Phoenix](https://www.phoenixframework.org/) 1.8 + LiveView 1.1
- [Svelte](https://svelte.dev/) via [live_svelte](https://github.com/woutdp/live_svelte)
- [SQLite](https://www.sqlite.org/) via [ecto_sqlite3](https://github.com/elixir-sqlite/ecto_sqlite3)
- [Tailwind CSS](https://tailwindcss.com/) v4
- [NATS](https://nats.io/) via [gnat](https://github.com/nats-io/nats.ex)
- [Oban](https://getoban.pro/) for background jobs
- [Heroicons](https://heroicons.com/) v2
