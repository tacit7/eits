# Pi Integration — Design Spec

**Date:** 2026-07-06
**Status:** Approved design, pre-implementation
**Scope:** Full claudette parity, shipped in three phases
**Prior art:** `~/projects/claudette` (Rust/Tauri host + Bun sidecar), whose Pi harness and ndjson protocol this design vendors and re-drives from Elixir.

## 1. Goal

Add **Pi** (`@earendil-works/pi-coding-agent`) as a third agent provider in EITS alongside Claude and Codex. Pi is itself multi-provider (OpenAI, Google, OpenRouter, xAI, GitHub Copilot, …), so one integration unlocks every model Pi can drive.

End state:

- Sessions can be spawned with `provider="pi"` and any Pi-qualified model id (`"openrouter/qwen3-coder"`, `"google/gemini-2.5-pro"`).
- Assistant text, thinking, and tool activity stream into the existing chat UI.
- Turns resume across the session's lifetime via Pi transcript persistence.
- Model discovery populates the spawn UI with actually-configured models.
- Provider auth (API keys + OAuth device-code) is manageable from `/settings`.
- Tool-approval cards render in chat when a session is not running with skip-permissions.

## 2. Architecture Overview

Pi plugs into the existing provider seam as a third `CLI` / `Parser` / `SDK` trio dispatched by `ProviderStrategy.for_provider/1`. No changes to AgentWorker, watchdog, retry, or cancel logic.

```
AgentWorker (unchanged)
  └─ ProviderStrategy.for_provider("pi") → ProviderStrategy.Pi
       └─ EyeInTheSky.Pi.SDK  (MessageHandler run-loop, shared SDK.Registry)
            └─ EyeInTheSky.Pi.CLI  (Port.open on the harness binary, ndjson both ways)
                 └─ pi-harness sidecar (vendored Bun/TS, wraps pi-coding-agent)
```

### Process model: spawn-per-turn + one-shot control processes

Unlike claudette (long-lived process per session), EITS spawns the harness **per turn**, matching how Claude/Codex already work:

1. Spawn harness → send `initialize` → `start_session` with the session's persistent `sessionDir` → `prompt`.
2. Stream events until `turn_end`.
3. Send `dispose`; process exits. `{:claude_exit, ...}` closes the run-loop normally.

Resume is free: `start_session` with the same `sessionDir` calls Pi's `SessionManager.continueRecent`, which reloads the most recent transcript in that directory. There is no resume flag and no async native-id sync (unlike Codex) — **we** name the directory, keyed by our own session UUID.

Everything that needs a live process — tool approvals, steering, compaction — happens *while a turn is in flight*, when the process is alive. Between turns nothing needs it.

Auth and model discovery use **separate one-shot harness invocations** (claudette's `pi_control` pattern): spawn → request → response → exit. The OAuth device-code flow is the one longer-lived control process (alive for the duration of the flow).

### sessionDir layout

`priv/pi-sessions/<eits-session-uuid>/` (git-ignored). The harness's `ready` event echoes back the sessionId we passed, so no id reconciliation is needed. `record_builder.resolve_provider_conversation_id` pre-generates/reuses the session UUID for `"pi"` (Claude-style, not Codex-style null).

## 3. The Vendored Harness (`pi-harness/`)

Copy claudette's `src-pi-harness/` to a top-level `pi-harness/` directory, renaming claudette-isms (binary name, identity preface wording). It is a self-contained Bun/TypeScript project:

- **Deps:** `@earendil-works/pi-coding-agent` (exact-pinned; claudette pins `0.74.0` — we adopt whatever current version we validate against) + `typebox`. Bun is required on the dev machine (already installed); the Phoenix asset pipeline is untouched.
- **Entry:** `pi-harness/src/main.ts` — readline loop over stdin, one JSON object per line, dispatched by `type`.
- **Build:** `scripts/build-pi-harness.sh` — `bun install --frozen-lockfile` → `bun run typecheck` → `bun build src/main.ts --compile --outfile priv/bin/eits-pi-harness` → copy the SDK's `package.json` to `priv/bin/pi/package.json` (the compiled binary reads it via `PI_PACKAGE_DIR` for version self-inspection).
- **Dev fallback:** if `priv/bin/eits-pi-harness` is absent, `Pi.CLI` runs `bun pi-harness/src/main.ts` directly.
- **Kept as-is from claudette:** workspace sandboxing (`assertInsideWorkspace`, symlink-safe writes, 2 MB read cap, 1 MB command-output cap), tool set (`read, ls, find, grep, bash, write, edit`), approval bounce-back, agent-loop event collapsing (`agent_start/end` → `turn_start/end`, per-LLM-round events swallowed), the identity system-prompt preface (reworded for EITS), and `provider-auth.ts` / `curated-providers.ts`.

### Wire protocol (unchanged from claudette)

Requests carry a host-assigned string `id`; responses echo it in an envelope `{id, type:"response", command, success, data?, error?}`. Unsolicited events have no `id`.

**Request verbs:** `initialize`, `start_session`, `prompt`, `steer`, `compact`, `abort`, `set_model`, `discover_models`, `auth_status`, `list_providers`, `set_api_key`, `clear_api_key`, `oauth_start`, `oauth_input`, `oauth_cancel`, `approve_tool`, `deny_tool`, `dispose`.

**Event types:** `ready`, `turn_start`, `assistant_delta`, `thinking_delta`, `tool_update`, `tool_result`, `tool_request`, `turn_end` (carries `aggregate`/`iteration` token usage + `totalCostUsd` + `durationMs`), `turn_error`, `compaction_start`, `compaction_end`, `oauth_challenge`, `oauth_progress`, `oauth_complete`, `error`, `exit`.

## 4. Elixir Modules

### `EyeInTheSky.Pi.CLI` (new, `lib/eye_in_the_sky/pi/cli.ex`)

- `spawn_new_session/2`, `resume_session/3` (identical internals — both start a turn against the sessionDir), `cancel/1`.
- Reuses `EyeInTheSky.CLI.Port` helpers (`spawn_handler`, `handle_port_output`, `cancel_port`, `find_binary`, `maybe_add_env`) and emits the shared `{:claude_output, ref, line}` / `{:claude_exit, ref, code}` tags.
- Key difference from Claude/Codex: **stdin stays open** and the CLI writes ndjson requests to the port (`Port.command`). No `script` pseudo-TTY wrapper, no `sh -c 'exec … </dev/null'`.
- Sends the turn preamble on spawn: `initialize` → `start_session{cwd, sessionId, sessionDir, model, thinkingLevel, allowedTools, customInstructions}` → `prompt{prompt}`.
- `send_request/2` public helper for mid-turn writes (`steer`, `compact`, `abort`, `approve_tool`, `deny_tool`) addressed by session ref via `SDK.Registry`.
- Env building: same EITS var injection as Claude/Codex (`EITS_SESSION_UUID/ID`, `EITS_PROJECT_ID`, `EITS_URL`, …), same secret stripping, plus `PI_PACKAGE_DIR`. `ANTHROPIC_API_KEY` stays stripped (Pi's Anthropic provider, if wanted, authenticates via `auth.json`) — subscription/OAuth tokens never reach the sidecar.
- Harness path resolution: `EITS_PI_HARNESS` env override → `priv/bin/eits-pi-harness` → dev fallback `bun pi-harness/src/main.ts`.

### `EyeInTheSky.Pi.Parser` (new)

`parse_stream_line/1` decodes one ndjson line and maps by `type`:

| Harness event | Parser output |
|---|---|
| `ready` | init message (session id confirmation; no UI content) |
| `assistant_delta` / `thinking_delta` | streaming text/thinking deltas |
| `tool_update` / `tool_result` | tool-use / tool-result messages |
| `tool_request` | approval-request message (Phase 3 surfaces it; Phase 1 never sees one because of bypassPermissions) |
| `turn_end` | result message with usage (`aggregate` tokens, `totalCostUsd`, `durationMs`) |
| `turn_error` | stashed error, folded into the turn result |
| `compaction_start/end` | status messages |
| `response` envelopes | acked/ignored (request bookkeeping lives in the SDK) |
| `error` / `exit` | error messages |

### `EyeInTheSky.Pi.SDK` (new)

Mirrors `Codex.SDK`: `use EyeInTheSky.SDK.MessageHandler`, registers ref→port in the shared `EyeInTheSky.Claude.SDK.Registry`, implements `handle_message/2`, `handle_result/2`, `resolve_exit_session_id/1`. On `turn_end` result: emit `{:claude_complete, ref, session_id}`, send `dispose`. Maintains a small request-id counter (`"pi-<n>"`) for the preamble and mid-turn requests; response envelopes are matched by id for error reporting.

### `EyeInTheSky.Claude.ProviderStrategy.Pi` (new) + seam edits

- Implements `start/2`, `resume/2`, `cancel/1`, `format_content/1`. `build_opts/2` maps job context → `{model, cwd, session_dir, allowed_tools, custom_instructions}`. EITS init prompt included as `customInstructions` (Codex-style prepend not needed — Pi supports system-prompt append natively).
- `allowedTools`: sessions with skip-permissions (the EITS default) pass `["*"]` → harness sets `bypassPermissions`, no approval cards. Otherwise the configured tool list.
- Edits: `ProviderStrategy.for_provider("pi")` (`provider_strategy.ex:44`), `pi_cli_module/0` in `utils.ex`, `stream_assembler_for("pi")` in `agent_worker.ex` (new `Pi.StreamAssembler` — delta-based like Claude's, not item-based like Codex's), `record_builder.resolve_provider/1` (`"pi" → "pi"`) and conversation-id pre-generation.

### `EyeInTheSky.Pi.Control` (new, Phase 2/3)

One-shot harness IPC for the non-chat verbs:

- `discover_models/0` → `{:ok, [%{id, provider, model_id, label, context_window, auth_source}]}`
- `list_providers/0`, `auth_status/0`
- `set_api_key/2`, `clear_api_key/1` → writes/removes entries in `~/.pi/agent/auth.json` (0600, file-locked by the SDK)
- `start_oauth/2` → longer-lived process; streams `oauth_challenge/progress/complete` events to the caller (a Settings LiveView) via PubSub; `oauth_input/2`, `oauth_cancel/1` write back to it.

**Auth decision:** `~/.pi/agent/auth.json` is the single credential store, shared with the terminal `pi`. Claudette's keychain/env-injection path is **dropped** — EITS is a single-user local server; one store is simpler and keys configured in the terminal Just Work in EITS and vice versa.

## 5. Metadata, Validation, UI, CLI

- **Model scheme:** `provider="pi"`, `model_name="<pi-provider>/<model-id>"` (e.g. `"openrouter/qwen3-coder"`). Sessions table unchanged.
- **`ModelConfig`:** add `"pi"` to `valid_model_combos/0`. Pi validation is **format-based** (`~r{^[\w.-]+/[\w.:-]+$}`), not enumerated — the true list comes from `discover_models` at spawn time. `default_model("pi")` picks the first discovered model; spawn fails with a clear error when none is configured.
- **`SpawnValidator`:** accept `"pi"`; validate model by format; surface "no Pi providers configured — add a key in /settings" when discovery is empty.
- **`ModelCapabilities`:** Pi models default to text-only (no vision) in Phase 1; revisit if needed.
- **`scripts/eits`:** add `pi` to `--provider` validation (~lines 1658–1748) with the same format-based model check, and forward it in `agents spawn`.
- **UI:** `dm_helpers.ex` — `provider_icon("pi")`, `provider_icon_class("pi")`, `stream_provider_label`. Spawn UI model picker: for `provider=pi`, populate from `Pi.Control.discover_models/0` (cached with short TTL).
- **Settings:** new "Pi Providers" section in `/settings` Auth tab — provider list with configured/unconfigured state, set/clear API key, "Sign in" button for OAuth providers driving the device-code flow (`oauth_challenge` URL + code display, progress, completion).

## 6. Tool Approvals (Phase 3)

Only `bash`, `write`, `edit` require approval, and only when the session is not `bypassPermissions`:

1. Harness emits `tool_request{requestId, toolCallId, kind, input}` mid-turn; the turn blocks on it.
2. Parser → SDK → AgentWorker → new `AgentWorkerEvents.on_tool_approval_requested/2` → PubSub → chat LiveView renders an approve/deny card (`kind: "commandExecution"` shows `{command, cwd, reason}`; `"fileChange"` shows a diff of `oldText`/`newText`).
3. User clicks → LiveView event → `Pi.CLI.send_request(ref, %{type: "approve_tool" | "deny_tool", requestId: ...})` to the live port.
4. `abort`/cancel denies all pending approvals (harness does this itself on `abort`).

Timeout policy: none at the harness level (matches claudette); the existing AgentWorker watchdog is **suspended while an approval is pending** so a human taking minutes to decide doesn't trip the idle kill.

## 7. Error Handling

- **Bad JSON / unknown event types:** parser returns an ignorable unknown marker (forward-compat, mirrors claudette's `#[serde(other)]`), logged at debug.
- **`turn_error` then `turn_end`:** error folded into the result message; AgentWorker retry/error-classifier logic applies unchanged.
- **Harness crash (`exit` event / nonzero exit):** flows through the existing `{:claude_exit, ref, code}` path → `on_sdk_errored` → retry policy.
- **No configured providers:** `start_session` fails; error surfaced verbatim in chat with a pointer to `/settings`.
- **Provider API failures mid-turn** (rate limits, auth): Pi SDK auto-retries internally and emits retry notices as `thinking_delta`; terminal failures arrive via `turn_error`.
- **Binary missing:** `find_binary`-style resolution failure produces an actionable error ("run scripts/build-pi-harness.sh").

## 8. Testing

- **Parser:** pure unit tests over recorded ndjson fixtures for every event type (deltas, tool lifecycle, turn_end usage shapes, turn_error folding, unknown types).
- **CLI/SDK:** the `pi_cli_module/0` seam allows a fake CLI in AgentWorker tests, mirroring the existing Claude/Codex test approach. One integration-style test drives a scripted fake harness (a small shell/bun script replaying a canned event stream) through the real Port path.
- **Control:** unit tests with a fake harness for discover/list/set-key; OAuth flow tested manually (device-code needs a real provider).
- **Harness itself:** claudette's code is treated as proven; we keep `bun run typecheck` in the build script and do not port its test suite.
- **Manual E2E per phase:** spawn a Pi session against a cheap OpenRouter model, verify streaming, resume, cancel, cost/usage display.

## 9. Phases

Each phase is its own worktree branch → Codex review → merge (per repo workflow).

**Phase 1 — Chat E2E (bypassPermissions):** vendored harness + build script + `Pi.{CLI,Parser,SDK,StreamAssembler}` + `ProviderStrategy.Pi` + seam edits + record_builder + minimal `ModelConfig`/validator acceptance + provider icon. Auth via pre-existing `~/.pi/agent/auth.json`. Exit criteria: spawn, stream, resume, cancel a Pi session from the UI.

**Phase 2 — Discovery & auth management:** `Pi.Control` (one-shot verbs), spawn-UI model picker fed by discovery, `/settings` Pi provider section (API keys set/clear), `scripts/eits` support.

**Phase 3 — Approvals & interactive turn control:** tool-approval cards + watchdog suspension, OAuth device-code flow in settings, steer + manual compact surfaced in chat UI.

## 10. Explicitly Out of Scope

- Ollama / LM Studio `providerOverride` injection (add later if local models are wanted).
- Keychain-stored keys with env injection (auth.json only).
- Vision/multimodal content blocks for Pi models.
- Remote-control/WSS routing for Pi sessions (matches claudette's exclusion).
- Migrating the Phoenix asset pipeline to Bun (separate task; Bun is used only inside `pi-harness/`).
