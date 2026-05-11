# Multi-Provider SDK Integration: Gemini

This document details how EITS integrates with the Gemini SDK to create, run, stream, and resume sessions. It follows the structure established by `docs/CODEX_SDK.md`.

## Provider Overview

| Provider | Binary | SDK | Stream Handler | Assembler | Status on Completion |
|----------|--------|-----|-----------------|-----------|----------------------|
| Gemini | `gemini` | `gemini_cli_sdk` | ETS-based `StreamHandler` | `StreamAssembler` | `idle` |

## Architecture

The Gemini integration follows a similar architecture to Codex, leveraging a dedicated `StreamHandler` for event translation.

## Module map

- `lib/eye_in_the_sky/claude/provider_strategy/gemini.ex` — implements the `ProviderStrategy` behaviour (`start/2`, `resume/2`, `cancel/1`, `format_content/1`). `build_opts/3` assembles a `%GeminiCliSdk.Options{}`. **No `system_prompt` field is set** (see §3 below).
- `lib/eye_in_the_sky/gemini/stream_handler.ex` — supervised `Task` that consumes GeminiCliSdk's lazy stream and translates events into the `{:claude_message, ref, %Message{}}` and `{:claude_complete, ref, session_id}` tuples that `AgentWorker` expects.
- `lib/eye_in_the_sky/gemini/stream_handler.ex` (nested `Registry`) — ETS-backed sdk_ref → pid map, auto-cleans on `:DOWN`.
- `lib/eye_in_the_sky/gemini/session_reader.ex` — locates + parses session files under `~/.gemini/tmp/<dir>/chats/`.
- `lib/eye_in_the_sky/gemini/session_importer.ex` — thin adapter over `EyeInTheSky.Messages.BulkImporter` for Reload/Sync.
- `lib/eye_in_the_sky/gemini/pricing.ex` — per-model $/1M token table (Gemini SDK doesn't return cost).
- `lib/mix/tasks/gemini.backfill_metadata.ex` — backfills legacy rows that landed without metadata.

## AgentWorker Integration

- `agent_worker.ex` provider polymorphism: `stream_assembler_for("gemini")` returns the **Codex** `StreamAssembler`, not Claude's. Gemini emits complete items per event (like Codex), not deltas-of-deltas (like Claude).
- The handler reuses Codex's `{:codex_session_id, ref, session_id}` channel to sync `provider_conversation_id` from `Types.InitEvent`.

## The GEMINI_SYSTEM_MD Landmine

The `gemini_cli_sdk` exposes `Options.system_prompt :: String.t()` and maps it to the `GEMINI_SYSTEM_MD` env var. **Gemini CLI interprets that env var as a path to a markdown file, not inline content.** Passing prompt text verbatim makes the CLI try to open() the text and crash with `Error: missing system prompt file '<the entire prompt>'`. We removed `system_prompt` from `build_opts/3` entirely. EITS context still reaches the agent via env vars (`EITS_SESSION_UUID`, `EITS_SESSION_ID`, `EITS_AGENT_UUID`, `EITS_PROJECT_ID`).

If a system prompt is ever needed: write to a temp file (e.g. `$TMPDIR/eits-gemini/system-<session_id>.md`) and pass that path. Note this **replaces** Gemini's default system prompt — no `--append` equivalent exists.

## MessageEvent: Delta vs Final (Doubled-Text Bug)

Gemini CLI emits TWO assistant `MessageEvent`s per turn:
- `delta: true` — incremental streaming chunk
- `delta: false`/nil — final aggregated content (sum of all preceding deltas)

Naively matching `role: "assistant"` and appending both leads to `state.text` ending up `chunks <> full_text` and the persisted bubble showing the answer twice. The `StreamHandler` now splits the clauses: deltas append + emit a delta Message; non-delta replaces `state.text` and only emits if no deltas preceded.

## Tool Use Shape

Emit `%Message{type: :tool_use, content: %{name: name, input: params}, metadata: %{tool_id: id}}`. The `Codex StreamAssembler` matches on `content: %{name: name, input: input}` to produce both `{:stream_delta, :tool_use, name}` and `{:stream_tool_input, name, input}`. Putting input under `metadata` instead leaves the tool block rendering as just the name with no inputs visible.

## Metadata Atom-Key Trap

`EyeInTheSky.AgentWorkerEvents.build_db_metadata/1` plucks fields via atom access: `metadata[:duration_ms]`, `metadata[:usage]`, `metadata[:total_cost_usd]`, etc. Returning a string-keyed map from `stats_to_map/2` makes every lookup return `nil` and the row persists with `metadata = NULL` — silent. Always emit atom keys at the boundary. The `Jason` encoder writes them as JSON strings on persist; consumers read them back as strings. One-way conversion is fine — the boundary just has to be atoms.

## Cost: Not from the SDK

`Types.ResultEvent.stats` only carries `total_tokens`, `input_tokens`, `output_tokens`, `duration_ms`, `tool_calls`. **No cost.** `EyeInTheSky.Gemini.Pricing` computes `total_cost_usd` from `tokens × per-model rate`:

- gemini-2.5-pro: $1.25 / $10 per 1M ($2.50 / $15 above 200k input)
- gemini-2.5-flash: $0.30 / $2.50 per 1M
- gemini-2.5-flash-lite: $0.10 / $0.40 per 1M

`Pricing.cost/3` and `Pricing.model_usage/3`. The DM metrics renderer reads both `metadata.total_cost_usd` and `metadata.model_usage` — populate both so the footer matches Claude/Codex.

The model has to be threaded from `build_opts/3` → `consume_stream/4` state because `ResultEvent.stats` doesn't include it.

## Session Files (Reload + Sync work for real)

Gemini CLI persists each chat at `~/.gemini/tmp/<project_dir>/chats/session-<ts>-<sessionId-prefix>.jsonl`. Layout:

- Line 1: manifest `{"sessionId", "projectHash", "startTime", "lastUpdated", "kind", "summary"}`.
- Each subsequent line: one turn.
  - user: `{"id", "timestamp", "type":"user", "content":[{"text":"..."}]}`
  - gemini: `{"id", "timestamp", "type":"gemini", "content":"...", "thoughts":[...], "tokens":{...}, "model":"...", "toolCalls":[...]}`

`projectHash = SHA-256(absolute project_path)` lowercase hex. Older Gemini CLI versions also use a friendly basename for the dir. `SessionReader.find_session_file/2` tries hash first, then basename, then scans `tmp/*/chats` as last resort. Match is confirmed by reading the manifest's `sessionId` (filename prefix is only 8 chars — not unique).

`SessionReader.read_messages/2` returns BulkImporter-shaped maps: `%{uuid, role, content, timestamp, usage, model, stream_type}`. Tool calls + `thoughts` are dropped — the live stream already renders them.

## Import metadata_fn (don't forget it)

`Messages.BulkImporter.import_messages/3` defaults `metadata_fn` to `fn _ -> nil end`. If `Gemini.SessionImporter.import_messages/2` doesn't pass a custom one, **every Reload-from-file or Sync run silently wipes the cost + tokens off Gemini agent rows.** The importer now passes a `build_metadata/1` that mirrors `StreamHandler.stats_to_map/3`'s output (usage + total_cost_usd + model_usage). Live-streamed and reloaded rows now produce identical metadata shape.

## DM Protocol: How Agents Recognize a DM from Another Agent

There is **no provider-level "this is an agent" flag**. It's a string convention enforced by EITS, not the underlying SDK or the LLM.

### Wire Format

`lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex:134` wraps every outgoing DM body as:

    DM from:<sender_name> (session:<sender_uuid>) <message body>

That envelope is generated server-side every time `eits dm --to X --message "..."` runs. The receiving agent gets the literal string as its next user-turn prompt — there is no out-of-band signal, header, or metadata visible to the SDK process. The wire is plain text.

### Receiver-Side Handshake

Every Claude / Codex / Gemini session that launches under EITS loads a skill called `eits-dm` (Claude/Gemini) or `codex-dm` (Codex). The skill's description triggers on exactly the prefix `"DM from:"`. Skill descriptions are bundled into the model's system context at session start, so when a prompt comes in beginning with `DM from:`, the router activates the skill's instructions: "this is another agent talking to you; here's how to reply via `eits dm --to <session_uuid>`."

The full chain is:

1. Sender invokes `eits dm --to <target> --message "<body>"`
2. REST controller resolves sender + receiver sessions, builds the envelope, calls `DMDelivery.deliver_and_persist/4`
3. Receiver wakes up (status `waiting`) or sees the prompt inline (status `working` / `idle`) — body arrives verbatim, no special framing
4. Receiver's skill manifest matches the `DM from:` prefix → `eits-dm` skill content loads → agent knows it's an inter-agent message and how to respond

### Stored vs Delivered

The `sender_name` and `from_session_uuid` are also written to `messages.metadata` for UI rendering (so the DM page can show the avatar + name on the bubble). But that's UI-only. The agent itself only sees the string in its prompt.

### Soft Failure Mode

This is a **textual handshake, not cryptographic**.

- Anyone (a human, an agent generating prose) typing `DM from:Pretend (session:00000000-...) hello` into a session would be indistinguishable from a real DM. The convention only holds because the only path that produces that string is the EITS DM pipeline.
- If skills are disabled, or the agent is fresh and hasn't loaded its skill manifest yet, the agent may just treat `DM from:...` as ordinary prose and respond conversationally instead of via the `eits dm` CLI. There's no enforcement in code — just convention.

For docs purposes: Gemini receives DMs the same way Claude/Codex do — as the next user prompt with the envelope prefix. The `eits-dm` skill should be loaded the same way (it's not Gemini-specific). The only Gemini-specific concern is that `GEMINI_SYSTEM_MD` is not set (see §3 of the previous onboarding), so skill content has to come through the project's `~/.gemini/skills/` directory or via the Gemini CLI's normal skill-discovery mechanism — verify that path works for Gemini sessions before claiming the protocol is end-to-end equivalent.

References:
- Envelope construction: `lib/eye_in_the_sky_web/controllers/api/v1/messaging_controller.ex:134`
- Delivery: `EyeInTheSky.Agents.DMDelivery.deliver_and_persist/4`
- UI prefix detection: `lib/eye_in_the_sky_web/components/dm_message_components.ex:167` (`String.starts_with?(raw_body, "DM from:")`)
- Receivable statuses: `@receivable_statuses ~w(working idle waiting)` in the same controller (DMs to `completed`/`failed` sessions return 422)

## UI Surface Gaps to Remember

When you add a new provider you must touch (this is what shipped for Gemini):

- `NewSessionModal` — provider dropdown + `provider_changed` default model
- `Components.NewAgentDrawer` — model select optgroup
- `Agents.SpawnValidator` — `default_model_for_provider/1`
- `DmLive.ExternalActions.build_resume_command/2` — open-in-iTerm
- `DmHelpers.provider_icon/1`, `provider_icon_class/1`, `stream_provider_label/1`
- `DmPage.MessagesTab.normalize_provider/1`, avatar, label
- `DmMessageComponents.stream_provider_avatar/1`
- `Rail.Flyout.canvas_provider_icon/1`
- `priv/static/images/gemini.svg`
- DM topbar Sync + Reload — both `MessageHandlers.sync_messages_from_session_file/1` AND `DmExportHelpers.handle_reload_from_session_file/2` now have a `"gemini"` branch (implemented in `4ff24598`). `sync_gemini_async/3` resolves the project path and delegates to `GeminiImporter.sync/3`. Reload drops all DB rows and re-imports from disk. `load_messages_on_mount/1` also syncs from the Gemini file on mount instead of returning an empty shape.

## `mix gemini.backfill_metadata`

For legacy rows that landed pre-metadata-fix. Reads tokens + model from the JSONL, computes cost via Pricing, merges into existing metadata. Starts Repo directly (skips `app.start`) so it doesn't collide with a running dev server on port 5001.

```
mix gemini.backfill_metadata               # all Gemini sessions
mix gemini.backfill_metadata --session ID  # one session
mix gemini.backfill_metadata --dry-run     # preview only
```

## Relevant Commits

- `93f379c8` — drop system_prompt
- `2a4cf857` — split delta vs final MessageEvent
- `be0f9848` — Codex assembler + tool_use shape + initial stats nesting
- `dd58d079` — atom keys for build_db_metadata
- `8660002e` — SessionReader + Importer + Reload/Sync wiring
- `d76fd7a5` — backfill task
- `0c645ba6` — Pricing + cost in metadata
- `c7457d37` — import path passes metadata_fn (no more silent wipe)
- `4ff24598` — real Reload + Sync wired for Gemini; sync_gemini_async helper; load_messages_on_mount syncs from Gemini file

## Dependencies

Gemini provider requires the following Hex package:

```elixir
# mix.exs
defp deps do
  [
    {:gemini_cli_sdk, "~> 0.2.0"},
    ...
  ]
end
```
The `gemini_cli_sdk` package provides:
- GeminiCliSdk binary discovery and management
- Event stream parsing (InitEvent, MessageEvent, ToolUseEvent, etc.)
- Session lifecycle APIs (start, resume, cancel)

## Key Modules

### Gemini
| Module | File | Role |
|--------|------|------|
| `Gemini.StreamHandler` | `lib/eye_in_the_sky/gemini/stream_handler.ex` | Consume GeminiCliSdk event streams, translate to Claude message tuples, ETS registry for lifecycle |
| `ProviderStrategy.Gemini` | `lib/eye_in_the_sky/claude/provider_strategy/gemini.ex` | Gemini-specific provider logic, routing |
| `Gemini.SessionReader` | `lib/eye_in_the_sky/gemini/session_reader.ex` | Read Gemini session messages from disk |
| `Gemini.SessionImporter` | `lib/eye_in_the_sky/gemini/session_importer.ex` | Incremental sync with watermark to avoid re-scanning history |
| `Gemini.Pricing` | `lib/eye_in_the_sky/gemini/pricing.ex` | Per-model token pricing for cost calculation |

### Shared
| Module | File | Role |
|--------|------|------|
| `StreamAssembler` | `lib/eye_in_the_sky/claude/stream_assembler.ex` | Stream state for Claude and Gemini PubSub events |
| `AgentWorker` | `lib/eye_in_the_sky/claude/agent_worker.ex` | Provider-polymorphic worker, struct-based dispatch for stream handling |
| `AgentManager` | `lib/eye_in_the_sky/claude/agent_manager.ex` | Session creation, worker lifecycle |
| `MessageHandler` | `lib/eye_in_the_sky/sdk/message_handler.ex` | JSONL parsing, raw Codex broadcasts when `forward_raw_lines: true` |
| `WorkerEvents` | `lib/eye_in_the_sky/agent_worker_events.ex` | DB persistence, PubSub broadcasts |

## Session Status Lifecycle

Gemini session status transitions are driven by events from the `gemini_cli_sdk` stream, translated by the `StreamHandler`.

| Gemini Event | Handler | Status Set |
|-------------|---------|------------|
| `InitEvent` | `StreamHandler` translation | `"working"` |
| `ResultEvent` | `StreamHandler` translation | `"idle"` |
| `ErrorEvent` | `StreamHandler` translation | `"idle"` |

**`InitEvent`**: When the Gemini stream starts with an `InitEvent`, the `StreamHandler` translates this to a status update that eventually sets the session to `"working"`.

**`ResultEvent`**: Upon receiving a `ResultEvent` from the Gemini CLI, indicating turn completion, the `StreamHandler` translates this to a status update that sets the session to `"idle"`.

**`ErrorEvent`**: If an `ErrorEvent` is received during a turn, the `StreamHandler` translates this to a status update that sets the session to `"idle"`, allowing the UI to display the failure and facilitate retries.

## EITS Environment Variables

Gemini sessions receive EITS env vars via the `build_opts/3` function in `lib/eye_in_the_sky/claude/provider_strategy/gemini.ex`.

Variables passed:

| Variable | Source | Description |
|----------|--------|-------------|
| `EITS_SESSION_UUID` | `state.provider_conversation_id` | Session UUID |
| `EITS_SESSION_ID` | `state.session_id` | EITS integer session ID |
| `EITS_AGENT_ID` | `state.agent_id` | Agent ID (UUID) |
| `EITS_PROJECT_ID` | `state.project_id` | EITS project integer ID |

## Init Prompt

Gemini sessions also utilize an initial prompt to inform the agent about available EITS CLI workflows, similar to Codex. The `format_content/1` function in `lib/eye_in_the_sky/claude/provider_strategy/gemini.ex` is responsible for preparing the initial prompt content.

## Known Issues and Gotchas

- **`GEMINI_SYSTEM_MD` as path**: As noted in "The GEMINI_SYSTEM_MD Landmine," `gemini_cli_sdk` interprets `GEMINI_SYSTEM_MD` as a file path, not inline content. Direct system prompts must be written to a temporary file.
- **Delta vs Final MessageEvent**: The `StreamHandler` must correctly differentiate and handle `delta: true` and `delta: false`/nil `MessageEvent`s to avoid duplicated text in the UI.
- **Cost not from SDK**: Gemini SDK does not provide cost information directly; it must be calculated using `EyeInTheSky.Gemini.Pricing`.
- **Atom-key trap**: Ensure metadata keys are atoms at the boundary for correct persistence and retrieval.
- **Skill content path**: Verify that skill content for Gemini sessions is correctly loaded from `~/.gemini/skills/` or via the Gemini CLI's normal skill-discovery mechanism, especially given the `GEMINI_SYSTEM_MD` limitation.
