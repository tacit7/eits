# docs/ — Documentation Index

- [SECURITY.md](SECURITY.md) — Auth, session handling, rate limiting, secrets, transport security
- [REST_API.md](REST_API.md) — Full API endpoint reference
- [SETUP.md](SETUP.md) — Project setup guide
- [CODE_GUIDELINES.md](CODE_GUIDELINES.md) — Coding standards
- [EITS_CLI.md](EITS_CLI.md) — CLI reference
- [EITS_HOOKS.md](EITS_HOOKS.md) — Hook system
- [DM_FEATURES.md](DM_FEATURES.md) — DM/messaging features
- [SESSION_MANAGER.md](SESSION_MANAGER.md) — Session lifecycle
- [WORKERS.md](WORKERS.md) — Background workers
- [AGENT_WORKER_QUEUE.md](AGENT_WORKER_QUEUE.md) — AgentWorker queue, message lifecycle states (pending→processing→delivered/failed), error paths
- [KANBAN.md](KANBAN.md) — Kanban board
- [COMMAND_PALETTE.md](COMMAND_PALETTE.md) — Command palette
- [chat-mention-workflow.md](chat-mention-workflow.md) — Chat @mention system
- [claude-cli-flags.md](claude-cli-flags.md) — Claude CLI flag reference
- [CONTEXT_WINDOW.md](CONTEXT_WINDOW.md) — Context window handling
- [SEARCH.md](SEARCH.md) — PgSearch implementation, prefix-aware tsquery
- [CODEX_SDK.md](CODEX_SDK.md) — Codex SDK: session lifecycle, JSONL events, resume flow
- [CHAT.md](CHAT.md) — Chat system: channels, routing, @mentions, cross-project membership
- [EVENTS.md](EVENTS.md) — PubSub Events: all topics, payload shapes, subscribe helpers
- [ORCHESTRATOR_TIMERS.md](ORCHESTRATOR_TIMERS.md) — OrchestratorTimers: session-scoped auto-nudge timers, PubSub events, UI integration
- [MOBILE.md](MOBILE.md) — Mobile layout standards: touch targets, sticky offsets, viewport, overflow
- [RAIL_MENU.md](RAIL_MENU.md) — Rail menu: section map, sticky sections, lazy loaders, project context, known project-persistence bug
- [WORKSPACE_SCOPE.md](WORKSPACE_SCOPE.md) — Workspace scope contract: Scope struct, WorkspaceLive.Hooks, cross-workspace ownership validation, canonical queries

## Claude API Key Blocking

`build_env/1` in `lib/eye_in_the_sky/claude/cli.ex` explicitly strips `ANTHROPIC_API_KEY` from the environment passed to spawned Claude processes:

```elixir
blocked_vars = ~w[CLAUDECODE CLAUDE_CODE_ENTRYPOINT ANTHROPIC_API_KEY]
```

**Why**: If the server process has `ANTHROPIC_API_KEY` set in its environment (e.g., a leftover dev key with no credits), spawned Claude subprocesses would pick it up and fail with `"Credit balance is too low"` billing errors instead of using the correct auth.

**How it works**: Without `ANTHROPIC_API_KEY`, the Claude CLI falls through to Max plan OAuth credentials stored in the macOS keychain. This is the intended auth path for spawned agents in this app — no API key needed, no DB storage of keys.

Common symptom when this goes wrong (key present and broke):
```json
{"type":"assistant","message":{"content":[{"type":"text","text":"Credit balance is too low"}]}}
```
Exit status will be 1 instead of 0.

## Session Status from Codex Events

Session status for Codex agents is driven by JSONL events emitted by `codex exec --json`, handled in `lib/eye_in_the_sky/agent_worker_events.ex`:

| Codex Event | Handler | Status Set |
|-------------|---------|------------|
| `thread.started` | `on_codex_thread_started/1` | `"working"` |
| `turn.completed` | `on_sdk_completed/3` (provider="codex") | `"waiting"` |
| SDK error | `on_sdk_errored/2` | `"idle"` |

**`thread.started`**: Fires when Codex creates a new thread. The worker calls `on_codex_thread_started/1` immediately (not waiting for turn end) to promote the session to `"working"` and sync the real `thread_id` to `sessions.uuid`.

**`turn.completed`**: Codex sessions go to `"waiting"` (not `"idle"`) on completion — they can be resumed with `codex exec resume <thread_id>`. Claude sessions go to `"idle"` instead.

See [CODEX_SDK.md](CODEX_SDK.md) for the full streaming pipeline and event type reference.
