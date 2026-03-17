# Codex SDK — Session Lifecycle

How EITS creates, runs, and resumes Codex (OpenAI) sessions.

## Architecture

```
UI (new agent form)
  → AgentManager.create_agent/1
    → create_records/1          (Agent + Session rows, uuid=nil for Codex)
    → send_message/3            (initial prompt)
      → lookup_or_start/2       (starts AgentWorker GenServer)
        → start_agent_worker/2  (auto-generates UUID if nil, saves to DB)
          → AgentWorker.init/1  (provider_conversation_id = session.uuid)
            → start_codex_sdk/2
              → Codex.SDK.start/2
                → Codex.CLI.spawn_new_session/2
                  → Port.open (codex exec --json ...)
```

## Session UUID Lifecycle

### Creation (uuid starts nil)

Codex sessions are created with `uuid = nil` in `create_records/1`:

```elixir
# agent_manager.ex
session_uuid = if provider == "codex", do: nil, else: Ecto.UUID.generate()
```

This is intentional. The real session identifier is the Codex **thread_id**, which is only known after `codex exec` starts running.

### Auto-generation fallback (start_agent_worker)

When the worker starts and `session.uuid` is nil, `start_agent_worker/2` generates a temporary UUID and saves it to the DB. This ensures `provider_conversation_id` is never nil in the worker state:

```elixir
# agent_manager.ex — start_agent_worker/2
session =
  if is_nil(session.uuid) or session.uuid == "" do
    uuid = Ecto.UUID.generate()
    {:ok, updated} = Sessions.update_session(session, %{uuid: uuid})
    updated
  else
    session
  end
```

### thread.started sync (the real ID)

When Codex starts, it emits a `thread.started` JSONL event with the real thread_id:

```json
{"type": "thread.started", "thread_id": "019cfa13-e9d3-7753-b6aa-f9cb878ac3eb"}
```

This flows through:

1. **Parser** returns `{:session_id, thread_id}`
2. **SDK handler** sends `{:codex_session_id, ref, thread_id}` to the worker immediately (not waiting for turn end)
3. **AgentWorker** receives it and calls `maybe_sync_provider_conversation_id/2`
4. **maybe_sync** updates the worker state AND writes the thread_id to `sessions.uuid` in the DB via `WorkerEvents.on_provider_conversation_id_changed/3`

After this point, `provider_conversation_id` in the worker is the real Codex thread_id.

## Resume Flow

On subsequent messages to the same session:

1. `AgentManager.send_message/3` calls `Messages.has_inbound_reply?(session_id, "codex")`
2. If true, `has_messages` is set in the context
3. `start_codex_sdk/2` calls `Codex.SDK.resume(thread_id, prompt, opts)`
4. CLI builds: `codex exec resume <thread_id> --json --full-auto ...`

Codex stores session history locally at `$CODEX_HOME/sessions` for up to 30 days.

## JSONL Event Types

Events emitted by `codex exec --json`:

| Event | Description | Key Fields |
|-------|-------------|------------|
| `thread.started` | New thread created | `thread_id` (UUID) |
| `turn.started` | Agent turn beginning | (none) |
| `item.started` | Work unit started | `item.id`, `item.type`, `item.status` |
| `item.completed` | Work unit finished | `item.id`, `item.type`, result data |
| `turn.completed` | Turn finished | `usage.input_tokens`, `usage.output_tokens` |
| `turn.failed` | Turn failed | `message` or `error` |
| `error` | Top-level error | `message` |

### Item Types

| Type | Description |
|------|-------------|
| `agent_message` | Text response (has `text` or `content` field) |
| `reasoning` | Thinking/reasoning (has `text` or `content` field) |
| `command_execution` | Shell command (has `command`, `exit_code`, `aggregated_output`) |
| `file_change` / `file_changes` | File modifications |
| `mcp_tool_call` / `mcp_tool_calls` | MCP tool invocations |
| `web_search` / `web_searches` | Web searches |
| `plan_update` / `plan_updates` | Plan modifications |

Note: Codex uses singular item type names (`file_change`, `mcp_tool_call`). The parser accepts both singular and plural forms.

## EITS Environment Variables

Codex sessions receive EITS env vars via two mechanisms:

### 1. Port environment (`build_env`)

Passed to the `codex` process itself via `Port.open {:env, env}`. These are available to the Codex binary but may be filtered by `shell_environment_policy` before reaching shell commands.

### 2. CLI `-c` flags (`build_args`)

Injected as `shell_environment_policy.set.VAR=value` args. These bypass Codex's default env var filtering (which excludes patterns like `KEY`, `SECRET`, `TOKEN`) and are available in all shell commands the agent runs.

Variables passed:

| Variable | Source | Description |
|----------|--------|-------------|
| `EITS_SESSION_UUID` | `state.provider_conversation_id` | Session UUID (may be temp until thread.started syncs) |
| `EITS_SESSION_ID` | `state.session_id` | EITS integer session ID |
| `EITS_AGENT_UUID` | `state.agent_id` | Agent UUID |
| `EITS_AGENT_ID` | `state.agent_id` | Agent ID (same as UUID) |
| `EITS_PROJECT_ID` | `state.project_id` | EITS project integer ID |
| `EITS_MODEL` | `context[:model]` | Model name (e.g., "o4-mini") |
| `EITS_URL` | hardcoded | `http://localhost:5000/api/v1` |

## Init Prompt

The first message to a new Codex session is prepended with `codex_eits_init/1`, which tells the agent about the available env vars and the `eits` CLI workflow for task tracking.

## Key Modules

| Module | File | Role |
|--------|------|------|
| `Codex.CLI` | `lib/eye_in_the_sky_web/codex/cli.ex` | Port spawning, arg building, env setup |
| `Codex.SDK` | `lib/eye_in_the_sky_web/codex/sdk.ex` | High-level API; message protocol adapter |
| `Codex.Parser` | `lib/eye_in_the_sky_web/codex/parser.ex` | JSONL line → Message struct |
| `Codex.StreamAssembler` | `lib/eye_in_the_sky_web/codex/stream_assembler.ex` | Stream state for PubSub events |
| `AgentWorker` | `lib/eye_in_the_sky_web/claude/agent_worker.ex` | Provider-polymorphic worker |
| `AgentManager` | `lib/eye_in_the_sky_web/claude/agent_manager.ex` | Session creation, worker lifecycle |
| `WorkerEvents` | `lib/eye_in_the_sky_web/claude/worker_events.ex` | DB persistence, PubSub broadcasts |

## Streaming vs Claude

| Aspect | Claude | Codex |
|--------|--------|-------|
| Output format | SSE (Server-Sent Events) | JSONL (one JSON object per line) |
| Text delivery | Character-by-character deltas | Complete blocks per item |
| Stream event | `{:stream_delta, :text, delta}` | `{:stream_replace, :text, text}` |
| Session ID source | First API response | `thread.started` event |
| Resume command | `claude --resume <uuid>` | `codex exec resume <thread_id>` |
| Local persistence | `~/.claude/sessions/` | `$CODEX_HOME/sessions/` (30 days) |
