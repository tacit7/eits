# Codex Integration

How EITS creates, runs, streams, and resumes Codex (OpenAI) sessions.

## Architecture

```
UI (new agent form, agent_type="codex")
  -> AgentManager.create_agent/1
    -> create_records/1          (Agent + Session rows, uuid=nil for Codex)
    -> send_message/3            (initial prompt)
      -> lookup_or_start/2       (starts AgentWorker GenServer)
        -> start_agent_worker/2  (auto-generates UUID if nil, saves to DB)
          -> AgentWorker.init/1  (stream = CodexStreamAssembler.new())
            -> start_codex_sdk/2
              -> Codex.SDK.start/2
                -> Codex.CLI.spawn_new_session/2
                  -> Port.open (codex exec --json ...)
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
# agent_manager.ex -- start_agent_worker/2
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

## Incremental Sync Watermark

The `SessionImporter` tracks the last synced message UUID to avoid re-scanning the entire session history on each sync:

```elixir
# codex/session_importer.ex
def sync(thread_id, session_id) do
  last_uuid = Messages.get_last_source_uuid(session_id)
  with {:ok, messages} <- SessionReader.read_messages_after_uuid(thread_id, last_uuid) do
    {:ok, import_messages(messages, session_id)}
  end
end
```

The watermark is stored by tracking the `source_uuid` of the last successfully imported message:

- `Messages.get_last_source_uuid(session_id)` returns the UUID of the most recent imported message for the session, or `nil` if no messages exist
- `SessionReader.read_messages_after_uuid(thread_id, after_uuid)` filters the file to return only messages with UUIDs that come after the watermark
- If `after_uuid` is `nil`, all messages are returned (first sync)
- If the watermark UUID is not found in the file (e.g., file rotated), all messages are returned as a fallback
- Each message imported updates the watermark, enabling resumable, incremental sync

## Streaming Pipeline

### Provider-Polymorphic Dispatch

AgentWorker uses struct-based dispatch to route stream events to the correct assembler module. The `stream` field in the worker state holds either a `%StreamAssembler{}` (Claude) or `%CodexStreamAssembler{}` (Codex):

```elixir
# AgentWorker.init/1
stream: stream_assembler_for(provider)

# Dispatch helpers pattern-match on struct type
defp stream_assembler_for("codex"), do: CodexStreamAssembler.new()
defp stream_assembler_for(_provider), do: StreamAssembler.new()

defp stream_handle_message(%CodexStreamAssembler{} = s, msg), do: CodexStreamAssembler.handle_message(s, msg)
defp stream_handle_message(%StreamAssembler{} = s, msg), do: StreamAssembler.handle_message(s, msg)
```

All message handlers in AgentWorker call these dispatch helpers instead of any assembler module directly.

### Codex.StreamAssembler

Unlike Claude's delta-based `StreamAssembler`, the Codex version handles complete items:

- **Text blocks** replace the buffer entirely (`{:stream_replace, :text, text}`)
- **Thinking blocks** emit `{:stream_replace, :thinking, text}`
- **Tool use** (partial/complete) emits `{:stream_delta, :tool_use, name}` and `{:stream_tool_input, name, input}`
- **Tool deltas and block stops** are no-ops (Codex items arrive complete)

The assembler implements the same interface as Claude's (`new/0`, `reset/1`, `buffer/1`, `handle_message/2`, `handle_tool_delta/2`, `handle_tool_block_stop/1`) so the worker dispatches uniformly.

### DM LiveView Streaming UI

The DM page renders stream events provider-aware:

- **Provider avatar**: Claude shows `claude.svg`, Codex shows `openai.svg`
- **Provider label**: "Claude" vs "Codex" in the stream bubble header
- **Thinking display**: Codex reasoning items render as italic text above tool/content output
- **Message provider**: User messages are tagged with the session's provider, not hardcoded "claude"

#### Stream Thinking Display

Thinking/reasoning content is captured in the `stream_thinking` socket assign during streaming:

```elixir
# lib/eye_in_the_sky_web_web/live/dm_live/stream_state.ex
def handle_stream_replace(:thinking, text, socket) do
  {:noreply, assign(socket, :stream_thinking, text)}
end
```

The `stream_thinking` assign:
- Holds the full thinking block text as it's streamed from Codex
- Is cleared on each new stream via `handle_stream_clear/1` (sets to `nil`)
- Allows the UI to display inline reasoning while the agent thinks
- Works for both complete blocks (Codex) and character-by-character deltas (Claude)

### Raw Output Broadcasting

Codex's raw JSONL output lines are broadcast directly from `MessageHandler` when `forward_raw_lines: true` is set in the SDK options. This is set in `Codex.SDK`'s `@loop_opts`:

```elixir
@loop_opts [
  parser: Parser,
  telemetry_prefix: [:eits, :codex, :sdk],
  log_raw_key: "log_codex_raw",
  log_raw_prefix: "codex.raw",
  forward_raw_lines: true
]
```

The broadcast uses the `eits_session_id` from the handler state (not the Codex thread_id):

```elixir
# lib/eye_in_the_sky/sdk/message_handler.ex
if forward_raw_lines do
  broadcast_id = Map.get(state, :eits_session_id) || session_id
  EyeInTheSky.Events.broadcast_codex_raw(broadcast_id, line)
end
```

This enables live debugging and inspection of the raw Codex JSONL stream without coupling the broadcast to AgentWorker. The `eits_session_id` ensures the broadcast reaches subscribers even before the Codex thread_id is available (before `thread.started` fires). Previously, AgentWorker relayed these messages; now the broadcast happens directly in MessageHandler.

## Sandbox Bypassing

By default, all Codex sessions bypass sandbox approval checks and tooling restrictions with the `--dangerously-bypass-approvals-and-sandbox` flag. This is configured in two places:

1. **RuntimeContext**: Sets `bypass_sandbox: true` by default for Codex provider:
   ```elixir
   bypass_sandbox: opts[:bypass_sandbox] || provider == "codex"
   ```

2. **Codex.CLI.build_args/1**: Defaults `bypass_sandbox` option to `true`:
   ```elixir
   if Keyword.get(opts, :bypass_sandbox, true) do
     args ++ ["--dangerously-bypass-approvals-and-sandbox"]
   else
     full_auto = Keyword.get(opts, :full_auto, true)
   ```

This allows Codex agents to use file modifications, shell commands, and other restricted operations by default. To opt out (use approval requirements), explicitly pass `bypass_sandbox: false` when starting a session.

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

### Tool Normalization (Codex.ToolMapper)

Codex tool calls are normalized into a canonical format for display and processing via `Codex.ToolMapper`:

- **`command_execution`** → `Bash` tool (extracts `command` field)
- **`web_search` / `web_searches`** → `WebSearch` tool (extracts `query` field)
- **`plan_update` / `plan_updates`** → `Task` tool (extracts `summary`, `explanation`, or `plan` field)
- **`mcp_tool_call` / `mcp_tool_calls`** → `mcp_{server}__{tool}` (extracts `server` and `tool` fields)
- **Any other tool** → Passed through as-is with stringified fields

This normalization allows the UI and downstream handlers to work with tool calls uniformly across different Codex versions and item type names.

## EITS Environment Variables

Codex sessions receive EITS env vars via two mechanisms:

### 1. Port environment (`build_env`)

Passed to the `codex` process itself via `Port.open {:env, env}`. These are available to the Codex binary but may be filtered by `shell_environment_policy` before reaching shell commands.

### 2. CLI `-c` flags (`build_args`)

Injected as `-c shell_environment_policy.set.VAR="value"` args. These bypass Codex's default env var filtering (which excludes patterns like `KEY`, `SECRET`, `TOKEN`) and are available in all shell commands the agent runs.

**Important**: All values MUST be quoted as TOML strings. Codex's config parser uses TOML, so bare integers like `1756` cause `invalid type: integer, expected a string` errors. The CLI wraps all values: `shell_environment_policy.set.KEY="value"`.

Variables passed:

| Variable | Source | Description |
|----------|--------|-------------|
| `EITS_SESSION_UUID` | `state.provider_conversation_id` | Session UUID (may be temp until thread.started syncs) |
| `EITS_SESSION_ID` | `state.session_id` | EITS integer session ID |
| `EITS_AGENT_ID` | `state.agent_id` | Agent ID (UUID) |
| `EITS_PROJECT_ID` | `state.project_id` | EITS project integer ID |
| `EITS_MODEL` | `context[:model]` | Model name (e.g., "o4-mini") |
| `EITS_URL` | hardcoded | `http://localhost:5001/api/v1` |

## Init Prompt

The first message to a new Codex session is prepended with `codex_eits_init/1`, which tells the agent about the available env vars and the `eits` CLI workflow for task tracking.

The init prompt uses the `@eits_cli_reference` module attribute to inject the canonical EITS CLI command reference:

```elixir
@eits_cli_reference """
  eits tasks begin --title "<title>"
  eits tasks annotate <id> --body "..."
  eits tasks update <id> --state 4
  eits dm --to <session_uuid> --message "<text>"
  eits commits create --hash <hash>
"""
```

This centralizes the CLI reference, ensuring all Codex sessions receive identical and up-to-date instructions.

## Key Modules

| Module | File | Role |
|--------|------|------|
| `Codex.CLI` | `lib/eye_in_the_sky/codex/cli.ex` | Port spawning, arg building, env setup; defaults `bypass_sandbox` to `true` |
| `Codex.SDK` | `lib/eye_in_the_sky/codex/sdk.ex` | High-level API; message protocol adapter; init prompt with EITS CLI reference |
| `Codex.ToolMapper` | `lib/eye_in_the_sky/codex/tool_mapper.ex` | Normalize Codex tool calls to canonical format (command_execution→Bash, web_search→WebSearch, etc.) |
| `Codex.Parser` | `lib/eye_in_the_sky/codex/parser.ex` | JSONL line -> Message struct |
| `Codex.StreamAssembler` | `lib/eye_in_the_sky/codex/stream_assembler.ex` | Stream state for Codex PubSub events |
| `Codex.ReviewInstructions` | `lib/eye_in_the_sky/codex/review_instructions.ex` | Build review prompt for GitHub PRs |
| `Claude.StreamAssembler` | `lib/eye_in_the_sky/claude/stream_assembler.ex` | Stream state for Claude PubSub events |
| `AgentWorker` | `lib/eye_in_the_sky/claude/agent_worker.ex` | Provider-polymorphic worker |
| `AgentManager` | `lib/eye_in_the_sky/claude/agent_manager.ex` | Session creation, worker lifecycle |
| `MessageHandler` | `lib/eye_in_the_sky/sdk/message_handler.ex` | JSONL parsing, raw Codex broadcasts when `forward_raw_lines: true` |
| `WorkerEvents` | `lib/eye_in_the_sky/agent_worker_events.ex` | DB persistence, PubSub broadcasts |

## Session Status Lifecycle

Codex session status transitions are driven by JSONL events emitted by `codex exec --json`, handled in `lib/eye_in_the_sky/agent_worker_events.ex`:

| Codex Event | Handler | Status Set |
|-------------|---------|------------|
| `thread.started` | `on_codex_thread_started/1` | `"working"` |
| `turn.completed` | `on_sdk_completed/2` | `"idle"` |
| SDK error | `on_sdk_errored/2` | `"idle"` |

**`thread.started`**: Fires when Codex creates a new thread. The worker calls `on_codex_thread_started/1` immediately (not waiting for turn end) to promote the session to `"working"` and sync the real `thread_id` to `sessions.uuid`.

**`turn.completed`**: Codex sessions transition to `"idle"` on completion, matching Claude behavior. Sessions are cleaned up normally; they do not park in a waiting state.

**SDK error**: Failed turns transition to `"idle"` so the UI can display the failure and allow retry.

## Streaming vs Claude

| Aspect | Claude | Codex |
|--------|--------|-------|
| Output format | SSE (Server-Sent Events) | JSONL (one JSON object per line) |
| Text delivery | Character-by-character deltas | Complete blocks per item |
| Stream assembler | `Claude.StreamAssembler` | `Codex.StreamAssembler` |
| Text event | `{:stream_delta, :text, delta}` | `{:stream_replace, :text, text}` |
| Thinking event | `{:stream_delta, :thinking, delta}` | `{:stream_replace, :thinking, text}` |
| Tool deltas | Accumulates JSON fragments | No-op (items arrive complete) |
| Session ID source | First API response | `thread.started` event |
| Resume command | `claude --resume <uuid>` | `codex exec resume <thread_id>` |
| Local persistence | `~/.claude/sessions/` | `$CODEX_HOME/sessions/` (30 days) |
| Binary | `claude` (Node.js) | `codex` (Rust) |
| Auth env var | `ANTHROPIC_API_KEY` | `OPENAI_API_KEY` |
| Completion status | `"idle"` | `"idle"` |

## Known Issues and Gotchas

- **TOML quoting**: All `-c shell_environment_policy.set.*` values must be double-quoted. Bare integers cause Codex to exit with code 1 and no output.
- **No stderr separation**: Codex CLI merges stderr into stdout (`:stderr_to_stdout`). Parse errors or startup failures appear as raw text lines, not structured JSONL.
- **Singular/plural item types**: Codex docs reference singular names (`file_change`) but some builds emit plural (`file_changes`). Parser accepts both.
- **thread_id vs session UUID**: The auto-generated fallback UUID is temporary. After `thread.started` fires, the real thread_id replaces it. Any external reference to the session UUID may see the old value if captured before sync.
- **Exit code 1 with no output**: Usually means a config error (bad model name, TOML parse failure, missing API key). The Codex binary validates config before producing any JSONL.
