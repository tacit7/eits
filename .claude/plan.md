# Phoenix MCP Server — Implementation Plan

## Goal
Add an MCP server to the Phoenix app using **Anubis MCP** (`anubis_mcp ~> 0.17`) with **Streamable HTTP** transport. Mirror the tools from the Go core so remote MCP clients can call them over HTTP at `POST /mcp`.

## What We Get
- Any MCP client (Claude Desktop, remote agents, custom clients) can connect to `https://localhost:4000/mcp`
- Same tool surface as the Go core, but backed by existing Phoenix contexts (no code duplication)
- Streamable HTTP: single endpoint, JSON responses for quick ops, SSE for long-running ones

## Architecture

```
Endpoint (plug before Router)
  └─ Anubis.Server.Transport.StreamableHTTP.Plug at /mcp
       └─ EyeInTheSkyWeb.MCP.Server (Anubis Server)
            ├─ EyeInTheSkyWeb.MCP.Tools.Session      (i-session)
            ├─ EyeInTheSkyWeb.MCP.Tools.Notes         (i-note-add, i-note-get, i-note-search)
            ├─ EyeInTheSkyWeb.MCP.Tools.Tasks         (i-todo)
            ├─ EyeInTheSkyWeb.MCP.Tools.Commits       (i-commits)
            ├─ EyeInTheSkyWeb.MCP.Tools.SessionContext (i-save/load-session-context)
            ├─ EyeInTheSkyWeb.MCP.Tools.Search         (i-session-search)
            ├─ EyeInTheSkyWeb.MCP.Tools.Speak          (i-speak)
            ├─ EyeInTheSkyWeb.MCP.Tools.Prompts        (i-prompt-get)
            ├─ EyeInTheSkyWeb.MCP.Tools.Nats           (i-nats-send, i-nats-listen, remote variants)
            ├─ EyeInTheSkyWeb.MCP.Tools.Chat           (i-chat-send, i-dm, i-chat-channel-list)
            ├─ EyeInTheSkyWeb.MCP.Tools.Projects       (i-project-add)
            └─ EyeInTheSkyWeb.MCP.Tools.Spawn          (i-spawn-agent, i-spawn-claude)
```

## Tools to Implement (Full Parity — 26 tools)

### Phase 1 — Core DB tools (use existing contexts directly)
1. `i-session` — `EyeInTheSkyWeb.Agents` / session creation + update
2. `i-end-session` — update session status
3. `i-session-info` — return current MCP session state
4. `i-commits` — `EyeInTheSkyWeb.Commits.create_commit/1`
5. `i-note-add` — `EyeInTheSkyWeb.Notes.create_note/1`
6. `i-note-get` — `EyeInTheSkyWeb.Notes.get_note!/1`
7. `i-note-search` — `EyeInTheSkyWeb.Notes` + FTS5
8. `i-session-search` — FTS5 search on sessions
9. `i-save-session-context` — `EyeInTheSkyWeb.Contexts`
10. `i-load-session-context` — `EyeInTheSkyWeb.Contexts`
11. `i-todo` — `EyeInTheSkyWeb.Tasks` (all 16 subcommands)
12. `i-prompt-get` — `EyeInTheSkyWeb.Prompts`
13. `i-project-add` — `EyeInTheSkyWeb.Projects`

### Phase 2 — System tools
14. `i-speak` — shell out to `say` command (macOS TTS)
15. `i-window` — shell out to AppleScript for active window
16. `i-sync-messages` — read .jsonl, insert via Messages context

### Phase 3 — Messaging tools
17. `i-nats-send` — `EyeInTheSkyWeb.NATS.Publisher`
18. `i-nats-listen` — NATS consumer query
19. `i-nats-send-remote` — connect to remote NATS, publish
20. `i-nats-listen-remote` — connect to remote NATS, consume
21. `i-chat-send` — insert message to channel
22. `i-dm` — spawn Claude CLI with message
23. `i-chat-channel-list` — `EyeInTheSkyWeb.Channels`

### Phase 4 — Agent spawning
24. `i-spawn-agent` — `EyeInTheSkyWeb.Claude.AgentManager`
25. `i-spawn-claude` — `EyeInTheSkyWeb.Claude.SDK`

## Steps

### 1. Add dependency
```elixir
{:anubis_mcp, "~> 0.17"}
```

### 2. Create MCP Server module
`lib/eye_in_the_sky_web/mcp/server.ex` — defines the Anubis Server, registers all tool components.

### 3. Create tool modules
One module per tool group under `lib/eye_in_the_sky_web/mcp/tools/`. Each uses `Anubis.Server.Component, type: :tool` with schema + execute callback. Execute callbacks delegate to existing Phoenix contexts.

### 4. Wire into supervision tree
Add `Anubis.Server.Registry` and `{EyeInTheSkyWeb.MCP.Server, transport: :streamable_http}` to `application.ex`.

### 5. Add Plug to Endpoint
Insert `Anubis.Server.Transport.StreamableHTTP.Plug` in `endpoint.ex` before the Router plug, mounted at `/mcp`.

### 6. Compile and test
`mix compile` then test with `curl` or MCP client against `POST /mcp`.

## File Changes Summary
- `mix.exs` — add `anubis_mcp` dep
- `lib/eye_in_the_sky_web/mcp/server.ex` — new
- `lib/eye_in_the_sky_web/mcp/tools/*.ex` — new (one per tool group)
- `lib/eye_in_the_sky_web/application.ex` — add to supervision tree
- `lib/eye_in_the_sky_web_web/endpoint.ex` — add Plug mount
