# Pi Integration — Design Spec

**Date:** 2026-07-06 (revised same day after design review)
**Status:** Approved design, lifecycle/security revisions incorporated
**Scope:** Full claudette parity, shipped in three phases
**Prior art:** `~/projects/claudette` (Rust/Tauri host + Bun sidecar), whose Pi harness and ndjson protocol this design vendors and re-drives from Elixir.

## 1. Goal

Add **Pi** (`@earendil-works/pi-coding-agent`) as a third agent provider in EITS alongside Claude and Codex. Pi is itself multi-provider (OpenAI, Google, OpenRouter, xAI, GitHub Copilot, …), so one integration unlocks every model Pi can drive.

End state:

- Sessions can be spawned with `provider="pi"` and any Pi-qualified model id (`"openrouter/qwen/qwen3-coder"`, `"google/gemini-2.5-pro"`).
- Assistant text, thinking, and tool activity stream into the existing chat UI.
- Turns resume across the session's lifetime via Pi transcript persistence.
- Model discovery populates the spawn UI with actually-configured models.
- Provider auth (API keys, then OAuth device-code) is manageable from `/settings`.
- Tool-approval cards render in chat when a session is not running with skip-permissions.

**Security assumption:** EITS is a trusted single-user local app. `bypassPermissions` (the EITS norm via skip-permissions) is only safe under that assumption; multi-user or remote deployments must not default to it. The harness enforces workspace sandboxing **even under bypassPermissions** — this is an invariant, not inherited behavior.

## 2. Architecture Overview

Pi plugs into the existing provider seam as a third `CLI` / `Parser` / `SDK` trio dispatched by `ProviderStrategy.for_provider/1`. No changes to AgentWorker, watchdog, retry, or cancel logic beyond the approval-pending state in Phase 3.

```
AgentWorker (unchanged)
  └─ ProviderStrategy.for_provider("pi") → ProviderStrategy.Pi
       └─ EyeInTheSky.Pi.SDK  (protocol owner: request ids, pending requests, MessageHandler run-loop)
            └─ EyeInTheSky.Pi.CLI  (transport only: Port.open, write ndjson, emit raw output/exit)
                 └─ pi-harness sidecar (vendored Bun/TS, wraps pi-coding-agent)
```

### Process model: spawn-per-turn + one-shot control processes

Unlike claudette (long-lived process per session), EITS spawns the harness **per turn**, matching how Claude/Codex already work:

1. Spawn harness → send `initialize` → `start_session` with the session's persistent `sessionDir` → `prompt`.
2. Stream events until `turn_end`.
3. Send `dispose` (best-effort); process exits.

Everything that needs a live process — tool approvals, steering, compaction — happens *while a turn is in flight*, when the process is alive. Between turns nothing needs it.

Auth and model discovery use **separate one-shot harness invocations** (claudette's `pi_control` pattern): spawn → request → response → exit. The OAuth device-code flow is the one longer-lived control process (alive for the duration of the flow).

### Runtime invariants

- One Pi harness process is spawned per turn.
- **Only one Pi turn may be active per EITS session UUID.** This is satisfied by existing architecture — AgentWorker is a single GenServer per session and its queue_manager queues incoming prompts while status is `:running` — but Phase 1 adds a test proving two concurrent prompts for one Pi session serialize (queue), never spawn two harnesses.
- A turn is successful **only after `turn_end`**. Port exit before `turn_end` is a failed turn — even with exit code 0 — unless the user canceled it.
- After `turn_end`, `dispose` is sent best-effort. Port closure before or after dispose is normal completion. If the port is still alive N seconds (default 5) after dispose, `cancel_port` kills it.
- Cancel sequence: send `abort` if stdin is still open → wait briefly (default 3 s) for `turn_end`/`turn_error`/exit → fall back to `cancel_port` (SIGTERM → SIGKILL). Canceled turns are not retried.
- Failed `response` envelopes for `initialize`, `start_session`, or `prompt` fail the turn immediately, before any streaming.
- Session resume depends entirely on the persisted `sessionDir`. Phase 1 explicitly validates Pi transcript semantics under: successful turn, canceled turn, crashed harness, repeated resume. If `continueRecent` can select an unintended transcript (more than one transcript per dir, or a half-written one becoming "most recent"), the harness must be adjusted to pin a stable per-session transcript file rather than "most recent".

### sessionDir layout

Runtime transcript data must **not** live in release-bundled `priv/`. Session root resolution (`EyeInTheSky.Pi.session_root/0`):

1. `EITS_PI_SESSION_ROOT` env var
2. app config `:eye_in_the_sky, :pi_session_root`
3. dev fallback: `Path.expand("var/pi-sessions")` (git-ignored: `/var/pi-sessions/`)

Each session uses `<root>/<eits-session-uuid>/`. The harness's `ready` event echoes back the sessionId we passed, so no id reconciliation is needed. `record_builder.resolve_provider_conversation_id` pre-generates/reuses the session UUID for `"pi"` (Claude-style, not Codex-style null).

## 3. The Vendored Harness (`pi-harness/`)

Copy claudette's `src-pi-harness/` to a top-level `pi-harness/` directory, renaming claudette-isms (binary name, identity preface wording). It is a self-contained Bun/TypeScript project:

- **Deps:** `@earendil-works/pi-coding-agent` (exact-pinned; claudette pins `0.74.0` — we adopt whatever current version we validate against) + `typebox`. Bun is required on the dev machine (already installed); the Phoenix asset pipeline is untouched.
- **Entry:** `pi-harness/src/main.ts` — readline loop over stdin, one JSON object per line, dispatched by `type`.
- **Build:** `scripts/build-pi-harness.sh` — `bun install --frozen-lockfile` → `bun run typecheck` → `bun build src/main.ts --compile --outfile priv/bin/eits-pi-harness` → copy the SDK's `package.json` to `priv/bin/pi/package.json` (the compiled binary reads it via `PI_PACKAGE_DIR` for version self-inspection).
- **Dev fallback:** if `priv/bin/eits-pi-harness` is absent, `Pi.CLI` runs `bun pi-harness/src/main.ts` directly.
- **Kept as-is from claudette:** workspace sandboxing (`assertInsideWorkspace`, symlink-safe writes, 2 MB read cap, 1 MB command-output cap), tool set (`read, ls, find, grep, bash, write, edit`), approval bounce-back, agent-loop event collapsing (`agent_start/end` → `turn_start/end`, per-LLM-round events swallowed), the identity system-prompt preface (reworded for EITS), and `provider-auth.ts` / `curated-providers.ts`.

### Wire protocol

Requests carry a host-assigned string `id`; responses echo it in an envelope `{id, type:"response", command, success, data?, error?}`. Unsolicited events have no `id`.

**Protocol versioning (EITS addition to the vendored harness):** `initialize` includes `{protocolVersion: 1, client: "eits", clientVersion: "<app vsn>"}`; the harness's response data echoes `protocolVersion`. Version mismatch fails startup with an actionable error ("rebuild the harness: scripts/build-pi-harness.sh"). Bump the version on any breaking change to event names or payload shapes.

**Request verbs:** `initialize`, `start_session`, `prompt`, `steer`, `compact`, `abort`, `set_model`, `discover_models`, `auth_status`, `list_providers`, `set_api_key`, `clear_api_key`, `oauth_start`, `oauth_input`, `oauth_cancel`, `approve_tool`, `deny_tool`, `dispose`.

**Event types:** `ready`, `turn_start`, `assistant_delta`, `thinking_delta`, `tool_update`, `tool_result`, `tool_request`, `turn_end` (carries `aggregate`/`iteration` token usage + `totalCostUsd` + `durationMs`), `turn_error`, `compaction_start`, `compaction_end`, `oauth_challenge`, `oauth_progress`, `oauth_complete`, `error`, `exit`.

## 4. Elixir Modules

**Ownership rule:** `Pi.SDK` owns the protocol — all host request ids (`"pi-<n>"`), pending-request bookkeeping, and preamble sequencing (`initialize` → `start_session` → `prompt`). `Pi.CLI` is transport only: it opens the port, writes encoded ndjson maps on request, and emits raw output/exit messages. Neither responsibility is split.

### `EyeInTheSky.Pi.CLI` (new, `lib/eye_in_the_sky/pi/cli.ex`)

- `spawn_harness/2` (opens the port; the SDK drives the preamble), `send_ndjson/2` (writes one encoded map + newline to the port), `cancel/1` (abort → wait → `cancel_port`, per the invariants above).
- Reuses `EyeInTheSky.CLI.Port` helpers (`spawn_handler`, `handle_port_output`, `cancel_port`, `find_binary`, `maybe_add_env`).
- **Compatibility shim, intentional:** emits the legacy wire tags `{:claude_output, ref, line}` / `{:claude_exit, ref, code}` required by the shared MessageHandler pipeline. These names are provider-neutral in practice; renaming them is out of scope for this integration.
- Key difference from Claude/Codex: **stdin stays open** for the turn's lifetime. No `script` pseudo-TTY wrapper, no `sh -c 'exec … </dev/null'`.
- Env building: same EITS var injection as Claude/Codex (`EITS_SESSION_UUID/ID`, `EITS_PROJECT_ID`, `EITS_URL`, …), same secret stripping, plus `PI_PACKAGE_DIR`. `ANTHROPIC_API_KEY` stays stripped — see §5 Settings copy for the user-facing statement of this.
- Harness path resolution: `EITS_PI_HARNESS` env override → `priv/bin/eits-pi-harness` → dev fallback `bun pi-harness/src/main.ts`. Missing binary produces an actionable error ("run scripts/build-pi-harness.sh").

### `EyeInTheSky.Pi.Parser` (new)

`parse_stream_line/1` decodes one ndjson line and maps by `type`:

| Harness event | Parser output |
|---|---|
| `ready` | init message (session id confirmation; no UI content) |
| `assistant_delta` / `thinking_delta` | streaming text/thinking deltas |
| `tool_update` / `tool_result` | tool-use / tool-result messages |
| `tool_request` | approval-request message (Phase 3 surfaces it; before Phase 3 the SDK auto-denies — see §6) |
| `turn_end` | result message with usage (`aggregate` tokens, `totalCostUsd`, `durationMs`) |
| `turn_error` | stashed error, folded into the turn result |
| `compaction_start/end` | status messages |
| `response` envelopes | passed to SDK bookkeeping: success envelopes for known requests are consumed silently; **failure envelopes become SDK errors** (preamble failures fail the turn) |
| `error` / `exit` | error messages |
| unknown `type` / malformed JSON | ignorable unknown marker, logged at debug (forward-compat) |

Partial-line buffering is handled by `CLI.Port.handle_port_output` (existing); the parser only ever sees complete lines. A test covers ndjson split across port chunks regardless.

### `EyeInTheSky.Pi.SDK` (new)

The EITS MessageHandler adapter — **not** the upstream Pi SDK. Mirrors `Codex.SDK`: `use EyeInTheSky.SDK.MessageHandler`, registers ref→port in the shared `EyeInTheSky.Claude.SDK.Registry`, implements `handle_message/2`, `handle_result/2`, `resolve_exit_session_id/1`.

- Owns request ids and the pending-request map; sends the preamble after spawn.
- Tracks whether `turn_end` has been observed. Port exit before `turn_end` → failed turn (normalized error). Port exit after → normal; emit `{:claude_complete, ref, session_id}` (legacy tag, same shim note as above).
- After `turn_end`: send `dispose` best-effort with the kill-after-timeout fallback.
- Exposes mid-turn request functions (`steer/2`, `compact/2`, `approve_tool/2`, `deny_tool/2`) addressed by session ref via the Registry.

### Error normalization

Before any failure reaches AgentWorker's retry classifier, the parser/SDK produce a normalized error:

```elixir
%{
  provider: "pi",
  model: model,
  category: :auth | :rate_limit | :network | :model_not_found | :tool_error | :unknown,
  retryable: boolean(),
  message: message,        # sanitized — never includes key material
  raw: sanitized_raw       # raw Pi error code/payload, secrets redacted
}
```

Category mapping is best-effort from Pi's error strings/codes; `:auth` and `:model_not_found` are non-retryable so the retry policy doesn't reincarnate a doomed request five times. Provider API failures mid-turn that Pi auto-retries internally surface as `thinking_delta` retry notices (harness behavior, kept).

### `EyeInTheSky.Claude.ProviderStrategy.Pi` (new) + seam edits

Namespace note: `EyeInTheSky.Claude.ProviderStrategy` is legacy naming (it hosts Codex today too); Pi follows it for consistency. Renaming the namespace is out of scope.

- Implements `start/2`, `resume/2` (identical internals — both start a turn against the sessionDir), `cancel/1`, `format_content/1`. `build_opts/2` maps job context → `{model, cwd, session_dir, allowed_tools, approval_mode, custom_instructions}`. EITS init prompt included as `customInstructions`.
- **Tools vs approval policy are distinct concepts** mapped onto the harness's single `allowedTools` field: internally we carry `allowed_tools` (list) and `approval_mode` (`:bypass | :require_for_mutating_tools`). `approval_mode: :bypass` (the skip-permissions norm) sends `allowedTools: ["*"]`, which the harness maps to all tools + `bypassPermissions=true`. Otherwise the explicit tool list is sent and mutating tools (`bash`, `write`, `edit`) trigger approvals. Canonical kind mapping: `bash → "commandExecution"`, `write`/`edit → "fileChange"`; read-only tools (`read, ls, find, grep`) never require approval — a conscious policy, acceptable under the single-user-local assumption.
- Edits: `ProviderStrategy.for_provider("pi")` (`provider_strategy.ex:44`), `pi_cli_module/0` in `utils.ex`, `stream_assembler_for("pi")` in `agent_worker.ex` (new `Pi.StreamAssembler` — delta-based like Claude's, not item-based like Codex's), `record_builder.resolve_provider/1` (`"pi" → "pi"`) and conversation-id pre-generation.

### `EyeInTheSky.Pi.Control` (new, Phase 2/3)

One-shot harness IPC for the non-chat verbs:

- `discover_models/0` → `{:ok, [%{id, provider, model_id, label, context_window, auth_source}]}`
- `list_providers/0`, `auth_status/0`
- `set_api_key/2` (provider id validated against the curated provider list), `clear_api_key/1` (removes only that provider's credential)
- Phase 3: `start_oauth/2` → longer-lived process; streams `oauth_challenge/progress/complete` events to a Settings LiveView via PubSub; `oauth_input/2`, `oauth_cancel/1` write back to it.

**Discovery cache** (`EyeInTheSky.Pi.ModelDiscoveryCache`): TTL 60 s; invalidated on `set_api_key`, `clear_api_key`, `oauth_complete`; manual refresh button in the spawn UI and settings.

### Auth store & security rules

`~/.pi/agent/auth.json` is the **single** credential store, shared with the terminal `pi`. Claudette's keychain/env-injection path is dropped — single-user local app, one store, keys configured in the terminal Just Work in EITS and vice versa.

Hard rules:

- All writes go through the Pi SDK's `AuthStorage` inside the harness — Elixir never reads or writes auth.json directly, and never copies keys or OAuth/refresh tokens into the EITS DB or session records.
- File 0600, parent dir 0700, writes atomic (temp file in same dir + rename) and file-locked. Claudette's `provider-auth.ts` already does 0600 + locking; atomic replace is verified/added when vendoring.
- Logs must redact API keys, OAuth tokens, refresh tokens, and auth payloads; harness `error` payloads are sanitized before display.

## 5. Metadata, Validation, UI, CLI

- **Model scheme:** `provider="pi"`, `model_name="<pi-provider>/<model-id>"`. The model-id segment may itself contain slashes (OpenRouter ids like `openrouter/qwen/qwen3-coder`). Sessions table unchanged.
- **Format validation:** `~r{^[A-Za-z0-9_.-]+/[A-Za-z0-9_.:/@+-]+$}` (no whitespace/control chars; `/`, `:`, `@` allowed in the model-id segment). A fixture test validates the regex against real ids returned by `discover_models` before freezing it.
- **`ModelConfig`:** add `"pi"` to `valid_model_combos/0` with format-based validation. **`default_model("pi")` returns `nil`** — ModelConfig stays pure config, no I/O. The spawn UI and `SpawnValidator` resolve the default Pi model from the discovery cache; when discovery returns no configured models, spawn is blocked with "no Pi providers configured — add a key in /settings".
- **`ModelCapabilities`:** Pi models default to text-only (no vision) in Phase 1; revisit if needed.
- **`scripts/eits`:** add `pi` to `--provider` validation (~lines 1658–1748) with the same format-based model check, and forward it in `agents spawn`. **Phase 1** (CLI spawning is part of the normal workflow).
- **UI:** `dm_helpers.ex` — `provider_icon("pi")`, `provider_icon_class("pi")`, `stream_provider_label`. Spawn UI model picker: for `provider=pi`, populate from the discovery cache.
- **Settings:** new "Pi Providers" section in `/settings` Auth tab — provider list with configured/unconfigured state, set/clear API key (Phase 2), "Sign in" OAuth device-code flow (Phase 3). Copy states explicitly: *"EITS Pi uses ~/.pi/agent/auth.json only. Environment credentials (including ANTHROPIC_API_KEY) are intentionally not passed into the harness."*

## 6. Tool Approvals (Phase 3)

Only `bash`, `write`, `edit` require approval, and only when `approval_mode != :bypass`:

1. Harness emits `tool_request{requestId, toolCallId, kind, input}` mid-turn; the turn blocks on it.
2. Parser → SDK → AgentWorker marks the run **`awaiting_approval`** in its state (in-memory; not persisted) and suspends idle/watchdog checks for that ref → `AgentWorkerEvents.on_tool_approval_requested/2` → PubSub → chat LiveView renders an approve/deny card (`"commandExecution"` shows `{command, cwd, reason}`; `"fileChange"` shows an `oldText`/`newText` diff).
3. Pending approvals live in AgentWorker state and are broadcast over PubSub — **not** tied to LiveView presence. A reconnecting LiveView reconstructs pending cards from worker state.
4. Watchdog resumes on any of: `tool_update`, `tool_result`, `turn_error`, `turn_end`, `exit`, or user approve/deny/cancel.
5. User decision → LiveView event → `Pi.SDK.approve_tool/2` / `deny_tool/2` with the matching `requestId`.
6. `abort`/cancel denies all pending approvals (harness does this itself on `abort`).

No approval timeout at the harness level (matches claudette); a human taking minutes must not trip the idle kill.

**Before Phase 3** (defense against misconfiguration): any unexpected `tool_request` is **automatically denied** by the SDK and surfaced as a configuration-error status message — a turn must never deadlock waiting for a card that can't render.

## 7. Error Handling

- **Bad JSON / unknown event types:** ignorable unknown marker, logged at debug (mirrors claudette's `#[serde(other)]`).
- **`turn_error` then `turn_end`:** error folded into the result; normalized error → AgentWorker retry classification.
- **`turn_error` with no `turn_end` / exit before `turn_end` (any exit code) / `exit` event:** failed turn via the normalized-error path → `on_sdk_errored` → retry policy (auth/model errors non-retryable).
- **Failed preamble response envelopes:** fail the turn immediately with the envelope's error (e.g. "no configured providers" → settings-directed message in chat).
- **Protocol version mismatch:** startup failure with rebuild instruction.
- **Binary missing:** actionable error ("run scripts/build-pi-harness.sh").

## 8. Testing

- **Parser (unit, ndjson fixtures):** every event type; usage shapes on `turn_end`; `turn_error` folding; unknown types; malformed lines.
- **Lifecycle (fake CLI via `pi_cli_module/0` seam + one scripted fake-harness integration test through the real Port path):**
  - exit 0 before `turn_end` → failed turn
  - exit nonzero before `turn_end` → failed turn
  - `turn_error` without `turn_end` → failed turn
  - `turn_error` followed by `turn_end` → error folded into result
  - malformed ndjson line → ignored, turn continues
  - ndjson split across port chunks → reassembled correctly
  - unexpected `tool_request` pre-Phase-3 → auto-denied + config error surfaced
  - cancel → `abort` written, then killed on timeout
  - `dispose` after `turn_end` with already-closed port → normal completion
  - failed `start_session` response → settings-directed error, no stream
  - two concurrent prompts for one Pi session → serialized by AgentWorker queue, single harness at a time
- **Resume (Phase 1 validation, scripted + one real-model manual pass):** resume after successful turn; resume after canceled turn; resume after crashed harness; repeated resume. Confirms `continueRecent` determinism or forces the pinned-transcript harness change (§2 invariants).
- **Control:** unit tests with a fake harness for discover/list/set-key; cache invalidation on key changes; OAuth flow tested manually (device-code needs a real provider).
- **Harness itself:** claudette's code treated as proven; `bun run typecheck` stays in the build script; its test suite is not ported.
- **Manual E2E per phase:** spawn a Pi session against a cheap OpenRouter model; verify streaming, resume, cancel, cost/usage display.

## 9. Phases

Each phase is its own worktree branch → Codex review → merge (per repo workflow).

**Phase 1 — Chat E2E (bypass approval mode):** vendored harness + protocol version check + build script + `Pi.{CLI,Parser,SDK,StreamAssembler}` + `ProviderStrategy.Pi` + seam edits + record_builder + session-root resolver (`var/pi-sessions`, git-ignored) + format validation + provider icon + minimal `scripts/eits` `--provider pi` support + auto-deny of unexpected approvals + the full lifecycle/cancel/crash/resume test list above. Auth via pre-existing `~/.pi/agent/auth.json`. Exit criteria: spawn, stream, resume, cancel a Pi session from UI and CLI; resume-semantics validation complete.

**Phase 2 — API-key auth + discovery:** `Pi.Control` one-shot verbs, `ModelDiscoveryCache` (TTL + invalidation + manual refresh), spawn-UI model picker fed by discovery, `/settings` Pi provider section with set/clear API key.

**Phase 3 — OAuth + approvals + interactive controls:** OAuth device-code flow in settings, tool-approval cards + `awaiting_approval` worker state + watchdog suspension, steer + manual compact surfaced in chat UI.

## 10. Explicitly Out of Scope

- Ollama / LM Studio `providerOverride` injection (add later if local models are wanted).
- Keychain-stored keys with env injection (auth.json only).
- Vision/multimodal content blocks for Pi models.
- Remote-control/WSS routing for Pi sessions (matches claudette's exclusion).
- Migrating the Phoenix asset pipeline to Bun (separate task; Bun is used only inside `pi-harness/`).
- Renaming the legacy `:claude_output`/`:claude_exit` wire tags or the `EyeInTheSky.Claude.ProviderStrategy` namespace.
