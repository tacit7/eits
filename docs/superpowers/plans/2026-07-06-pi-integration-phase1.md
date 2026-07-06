# Pi Integration Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spawn, stream, resume, and cancel a Pi (`@earendil-works/pi-coding-agent`) session from the EITS UI and CLI, per the approved spec `docs/superpowers/specs/2026-07-06-pi-integration-design.md` (Phase 1: chat E2E, bypass approval mode).

**Architecture:** A vendored Bun/TypeScript sidecar (`pi-harness/`) speaks newline-delimited JSON on stdio. Elixir drives it as a third provider trio: `Pi.CLI` (transport: open port, write ndjson), `Pi.Parser` (line → Message/protocol tuples), `Pi.SDK` (request ids, preamble sequencing, turn lifecycle) behind `ProviderStrategy.for_provider("pi")`. One harness process per turn; resume via persistent `sessionDir`.

**Tech Stack:** Elixir/Phoenix (BEAM Ports), Bun + TypeScript (harness), ExUnit, `bun test` (harness sandbox tests).

## Global Constraints (from spec — every task inherits these)

- A turn is successful **only after `turn_end`**; port exit before `turn_end` (any exit code) is a failed turn unless canceled.
- Exactly one terminal outcome per ref: `nil | :completed | :failed | :canceled` guard in SDK state.
- `turn_error` is sticky: a following `turn_end` folds usage into the error; the turn stays failed.
- Harness `exit` event is diagnostic; OS port exit is authoritative.
- `Pi.SDK` owns all request ids (`"pi-<n>"`), pending-request bookkeeping, preamble sequencing, and the protocol verbs `abort`/`dispose`. `Pi.CLI` is transport-only.
- Startup ordering: `initialize` response (with `protocolVersion: 1` match) → `start_session` response **and** `ready` event (either order) → `prompt`.
- Env is **allowlist-based**: only `PATH`, `HOME`, `LANG`/`LC_*`, `TMPDIR`, `PI_PACKAGE_DIR`, `EITS_PI_TURN_ID`, and `EITS_*` vars reach the harness. No provider credential env vars, ever.
- Session root: `EITS_PI_SESSION_ROOT` env → app config `:pi_session_root` → `Path.expand("var/pi-sessions")`.
- Model naming: `provider="pi"`, model `~r{^[A-Za-z0-9_.-]+/[A-Za-z0-9_.:/@+-]+$}`, split with `String.split(model, "/", parts: 2)` only.
- Phase 1 auto-denies any unexpected `tool_request` (bypassPermissions is the only supported mode).
- MessageHandler extension callbacks must preserve existing Claude/Codex behavior exactly (default impls).
- Legacy wire tags `{:claude_output, ...}` / `{:claude_exit, ...}` / `{:claude_complete, ...}` are kept (intentional shim).
- Run `mix compile --warnings-as-errors` before every commit. No Anthropic attribution in commit messages.
- Work happens in a worktree branch (`.claude/worktrees/pi-phase1`, branch `pi-phase1`), per repo policy.

## File Structure

```
pi-harness/                                    # vendored Bun sidecar (Task 1)
  package.json, tsconfig.json, bun.lock
  src/main.ts, src/provider-auth.ts, src/curated-providers.ts, src/format-error.ts
  test/sandbox.test.ts                         # Task 12
scripts/build-pi-harness.sh                    # Task 2
lib/eye_in_the_sky/pi.ex                       # session_root/0, session_dir/1 (Task 3)
lib/eye_in_the_sky/pi/cli.ex                   # transport (Task 6)
lib/eye_in_the_sky/pi/parser.ex                # (Task 5)
lib/eye_in_the_sky/pi/sdk.ex                   # (Task 7)
lib/eye_in_the_sky/sdk/message_handler.ex      # extension callbacks (Task 4)
lib/eye_in_the_sky/claude/provider_strategy.ex # dispatch clause (Task 8)
lib/eye_in_the_sky/claude/provider_strategy/pi.ex  # (Task 8)
lib/eye_in_the_sky/claude/utils.ex             # pi_cli_module/0 (Task 8)
lib/eye_in_the_sky/agents/agent_manager/record_builder.ex  # (Task 8)
lib/eye_in_the_sky/agents/model_config.ex      # (Task 9)
lib/eye_in_the_sky/agents/spawn_validator.ex   # (Task 9)
lib/eye_in_the_sky_web/components/dm_helpers.ex  # (Task 9)
scripts/eits                                   # --provider pi (Task 10)
test/eye_in_the_sky/pi/…                       # Tasks 3–11
test/support/pi_fake_harness.exs + priv scripts # Task 11/13
```

---

### Task 1: Vendor the Pi harness

**Files:**
- Create: `pi-harness/` (copied from `~/projects/claudette/src-pi-harness/`)
- Modify: `pi-harness/package.json`, `pi-harness/src/main.ts` (targeted edits below)

**Interfaces:**
- Produces: a runnable sidecar — `bun pi-harness/src/main.ts` reads ndjson requests on stdin, writes responses/events on stdout. `initialize` response data includes `protocolVersion: 1`.

- [ ] **Step 1: Copy the harness source (not node_modules, not dist)**

```bash
mkdir -p pi-harness
cp -R ~/projects/claudette/src-pi-harness/src pi-harness/src
cp ~/projects/claudette/src-pi-harness/package.json pi-harness/package.json
cp ~/projects/claudette/src-pi-harness/tsconfig.json pi-harness/tsconfig.json
cp ~/projects/claudette/src-pi-harness/bun.lock pi-harness/bun.lock 2>/dev/null || true
```

- [ ] **Step 2: De-claudette the package**

In `pi-harness/package.json`: change `"name"` to `"@eits/pi-harness"`. Keep the exact-pinned `@earendil-works/pi-coding-agent` and `typebox` deps unchanged.

In `pi-harness/src/main.ts`:
1. Grep for `claudette`/`Claudette` (`grep -in claudette pi-harness/src/*.ts`) and replace user-visible occurrences with `EITS` (identity system-prompt preface, log strings). Do **not** rename protocol fields.
2. Find the `initialize` case in the request dispatcher (`handle()`) — it currently responds with `{ version: "<sdk version>" }`. Change the response data to also include the protocol version:

```typescript
case "initialize": {
  return { version: PI_VERSION, protocolVersion: 1 };
}
```

(Adapt to the local shape — the key requirement: `initialize` response `data` gains `protocolVersion: 1`. If the request payload includes `protocolVersion` and it is a number ≠ 1, throw `new Error(\`unsupported protocolVersion ${v}; expected 1 — rebuild the harness: scripts/build-pi-harness.sh\`)`.)

- [ ] **Step 3: Install and typecheck**

```bash
cd pi-harness && bun install && bun run typecheck && cd ..
```

Expected: exit 0, no type errors.

- [ ] **Step 4: Manual smoke — initialize round-trip**

```bash
printf '{"id":"pi-1","type":"initialize","protocolVersion":1}\n' | timeout 30 bun pi-harness/src/main.ts | head -1
```

Expected: one line: `{"id":"pi-1","type":"response","command":"initialize","success":true,"data":{"version":"…","protocolVersion":1}}`

- [ ] **Step 5: Add node_modules to .gitignore and commit**

Append to `.gitignore`:

```
/pi-harness/node_modules/
/pi-harness/dist/
/priv/bin/eits-pi-harness
/priv/bin/pi/
/var/pi-sessions/
```

```bash
git add pi-harness .gitignore
git commit -m "feat(pi): vendor pi-harness sidecar from claudette with protocolVersion handshake"
```

---

### Task 2: Build script

**Files:**
- Create: `scripts/build-pi-harness.sh`

**Interfaces:**
- Produces: `priv/bin/eits-pi-harness` (compiled binary) and `priv/bin/pi/package.json` (for `PI_PACKAGE_DIR`).

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Build the Pi harness sidecar into priv/bin/.
# Usage: scripts/build-pi-harness.sh [--skip-typecheck]
set -euo pipefail
cd "$(dirname "$0")/.."

command -v bun >/dev/null || { echo "error: bun not found on PATH (install: https://bun.sh)"; exit 1; }

pushd pi-harness >/dev/null
bun install --frozen-lockfile
if [[ "${1:-}" != "--skip-typecheck" ]]; then
  bun run typecheck
fi
popd >/dev/null

mkdir -p priv/bin/pi
bun build pi-harness/src/main.ts --compile --outfile priv/bin/eits-pi-harness
chmod +x priv/bin/eits-pi-harness
cp pi-harness/node_modules/@earendil-works/pi-coding-agent/package.json priv/bin/pi/package.json
echo "built priv/bin/eits-pi-harness"
```

- [ ] **Step 2: Run it**

```bash
chmod +x scripts/build-pi-harness.sh && scripts/build-pi-harness.sh
```

Expected: `built priv/bin/eits-pi-harness`; `priv/bin/eits-pi-harness` exists and is executable; `priv/bin/pi/package.json` exists.

- [ ] **Step 3: Smoke the compiled binary**

```bash
printf '{"id":"pi-1","type":"initialize","protocolVersion":1}\n' | PI_PACKAGE_DIR="$PWD/priv/bin/pi" timeout 30 priv/bin/eits-pi-harness | head -1
```

Expected: same successful initialize response as Task 1 Step 4.

- [ ] **Step 4: Commit**

```bash
git add scripts/build-pi-harness.sh
git commit -m "feat(pi): add pi-harness build script (bun compile to priv/bin)"
```

---

### Task 3: Session root resolver

**Files:**
- Create: `lib/eye_in_the_sky/pi.ex`
- Test: `test/eye_in_the_sky/pi_test.exs`

**Interfaces:**
- Produces: `EyeInTheSky.Pi.session_root/0 :: String.t()` and `EyeInTheSky.Pi.session_dir(session_uuid :: String.t()) :: String.t()` (creates the dir).

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EyeInTheSky.PiTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi

  setup do
    original = Application.get_env(:eye_in_the_sky, :pi_session_root)
    on_exit(fn ->
      System.delete_env("EITS_PI_SESSION_ROOT")
      if original,
        do: Application.put_env(:eye_in_the_sky, :pi_session_root, original),
        else: Application.delete_env(:eye_in_the_sky, :pi_session_root)
    end)
    :ok
  end

  test "env var wins over app config and default" do
    System.put_env("EITS_PI_SESSION_ROOT", "/tmp/pi-env-root")
    Application.put_env(:eye_in_the_sky, :pi_session_root, "/tmp/pi-cfg-root")
    assert Pi.session_root() == "/tmp/pi-env-root"
  end

  test "app config wins over default" do
    System.delete_env("EITS_PI_SESSION_ROOT")
    Application.put_env(:eye_in_the_sky, :pi_session_root, "/tmp/pi-cfg-root")
    assert Pi.session_root() == "/tmp/pi-cfg-root"
  end

  test "defaults to var/pi-sessions" do
    System.delete_env("EITS_PI_SESSION_ROOT")
    Application.delete_env(:eye_in_the_sky, :pi_session_root)
    assert Pi.session_root() == Path.expand("var/pi-sessions")
  end

  test "session_dir builds and creates the per-session directory" do
    tmp = Path.join(System.tmp_dir!(), "pi-root-#{System.unique_integer([:positive])}")
    System.put_env("EITS_PI_SESSION_ROOT", tmp)
    dir = Pi.session_dir("abc-123")
    assert dir == Path.join(tmp, "abc-123")
    assert File.dir?(dir)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/eye_in_the_sky/pi_test.exs`
Expected: FAIL — `EyeInTheSky.Pi is not available`.

- [ ] **Step 3: Implement**

```elixir
defmodule EyeInTheSky.Pi do
  @moduledoc """
  Pi provider namespace helpers.

  Session transcripts persist under `session_root()/<eits-session-uuid>/`.
  Runtime transcript data must never live in release-bundled priv/.
  """

  @doc """
  Resolution order: EITS_PI_SESSION_ROOT env var, app config
  `:pi_session_root`, then `var/pi-sessions` relative to the app root.
  """
  @spec session_root() :: String.t()
  def session_root do
    System.get_env("EITS_PI_SESSION_ROOT") ||
      Application.get_env(:eye_in_the_sky, :pi_session_root) ||
      Path.expand("var/pi-sessions")
  end

  @doc "Returns (and creates) the transcript directory for a session UUID."
  @spec session_dir(String.t()) :: String.t()
  def session_dir(session_uuid) when is_binary(session_uuid) do
    dir = Path.join(session_root(), session_uuid)
    File.mkdir_p!(dir)
    dir
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/eye_in_the_sky/pi_test.exs`
Expected: 4 tests, 0 failures.

- [ ] **Step 5: Compile clean and commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/pi.ex test/eye_in_the_sky/pi_test.exs
git commit -m "feat(pi): session root resolver (env > config > var/pi-sessions)"
```

---

### Task 4: MessageHandler extension callbacks

**Files:**
- Modify: `lib/eye_in_the_sky/sdk/message_handler.ex`
- Test: `test/eye_in_the_sky/sdk/message_handler_extension_test.exs`

**Interfaces:**
- Produces (used by Task 7):
  - New optional callback `handle_protocol_event(data :: map(), state) :: {:continue, state} | {:halt, reason :: term()}` — dispatched when a parser returns `{:protocol, data}`. On `{:halt, reason}` the loop sends `{:claude_error, sdk_ref, reason}` and stops.
  - New optional callback `on_clean_exit(state) :: {:complete, session_id :: String.t() | nil} | {:error, reason :: term()}` — replaces the hardcoded exit-0-success branch. Default: `{:complete, resolve_exit_session_id(state)}` (existing behavior, exactly).

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule EyeInTheSky.SDK.MessageHandlerExtensionTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.SDK.MessageHandler

  defmodule FakeParser do
    # line IS the instruction, keeps tests declarative
    def parse_stream_line("protocol:" <> rest), do: {:protocol, %{"raw" => rest}}
    def parse_stream_line("skip"), do: :skip
    def parse_stream_line(_), do: :skip
  end

  defmodule DefaultSDK do
    use EyeInTheSky.SDK.MessageHandler
    def handle_message(_msg, state), do: {:continue, state}
    def handle_result(_data, _state), do: :ok
  end

  defmodule PiLikeSDK do
    use EyeInTheSky.SDK.MessageHandler
    def handle_message(_msg, state), do: {:continue, state}
    def handle_result(_data, _state), do: :ok

    def handle_protocol_event(%{"raw" => "boom"}, _state), do: {:halt, :preamble_failed}
    def handle_protocol_event(data, state) do
      send(state.caller_pid, {:protocol_seen, data})
      {:continue, state}
    end

    def on_clean_exit(%{turn_end_seen: true} = state), do: {:complete, state[:session_id]}
    def on_clean_exit(_state), do: {:error, :exit_before_turn_end}
  end

  defp run_handler(module, extra_state \\ %{}) do
    parent = self()
    sdk_ref = make_ref()
    state = Map.merge(%{sdk_ref: sdk_ref, caller_pid: parent, session_id: "s1"}, extra_state)
    pid = spawn(fn -> MessageHandler.run_loop(module, state, parser: FakeParser) end)
    {sdk_ref, pid}
  end

  test "default modules keep exit-0-is-success behavior (Claude/Codex unchanged)" do
    {sdk_ref, pid} = run_handler(DefaultSDK)
    send(pid, {:claude_exit, :cli_ref, 0})
    assert_receive {:claude_complete, ^sdk_ref, "s1"}, 1_000
  end

  test "default modules ignore protocol events (skip-equivalent)" do
    {sdk_ref, pid} = run_handler(DefaultSDK)
    send(pid, {:claude_output, :cli_ref, "protocol:whatever"})
    send(pid, {:claude_exit, :cli_ref, 0})
    assert_receive {:claude_complete, ^sdk_ref, "s1"}, 1_000
    refute_received {:claude_error, ^sdk_ref, _}
  end

  test "handle_protocol_event receives protocol data" do
    {_sdk_ref, pid} = run_handler(PiLikeSDK, %{turn_end_seen: true})
    send(pid, {:claude_output, :cli_ref, "protocol:hello"})
    assert_receive {:protocol_seen, %{"raw" => "hello"}}, 1_000
  end

  test "handle_protocol_event halt emits claude_error and stops" do
    {sdk_ref, pid} = run_handler(PiLikeSDK, %{turn_end_seen: false})
    send(pid, {:claude_output, :cli_ref, "protocol:boom"})
    assert_receive {:claude_error, ^sdk_ref, :preamble_failed}, 1_000
    refute Process.alive?(pid) || :sys.get_state(pid) == nil
  end

  test "on_clean_exit can turn exit-0 into an error (Pi invariant)" do
    {sdk_ref, pid} = run_handler(PiLikeSDK, %{turn_end_seen: false})
    send(pid, {:claude_exit, :cli_ref, 0})
    assert_receive {:claude_error, ^sdk_ref, :exit_before_turn_end}, 1_000
  end

  test "on_clean_exit completes when turn_end was seen" do
    {sdk_ref, pid} = run_handler(PiLikeSDK, %{turn_end_seen: true})
    send(pid, {:claude_exit, :cli_ref, 0})
    assert_receive {:claude_complete, ^sdk_ref, "s1"}, 1_000
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/eye_in_the_sky/sdk/message_handler_extension_test.exs`
Expected: FAIL — protocol tuple crashes the loop's `case` (no `{:protocol, _}` clause) and `on_clean_exit` is never consulted.

- [ ] **Step 3: Implement in `message_handler.ex`**

Add to the behaviour section (after `resolve_exit_session_id` docs):

```elixir
  @doc """
  Called when the parser emits `{:protocol, data}` (provider protocol
  bookkeeping such as request/response envelopes). Default: continue,
  ignoring the event — existing providers never emit it.
  """
  @callback handle_protocol_event(data :: map(), state :: state()) ::
              {:continue, state()} | {:halt, term()}

  @doc """
  Called on clean process exit (exit code 0). Default preserves legacy
  behavior: complete with `resolve_exit_session_id/1`. Providers whose
  success requires an explicit terminal event (Pi: `turn_end`) override
  this to return `{:error, reason}` when the event was never seen.
  """
  @callback on_clean_exit(state :: state()) ::
              {:complete, String.t() | nil} | {:error, term()}
```

Update the optional list:

```elixir
  @optional_callbacks [
    on_session_id: 2,
    resolve_exit_session_id: 1,
    handle_protocol_event: 2,
    on_clean_exit: 1
  ]
```

In `__using__`, add defaults and make them overridable:

```elixir
      @impl EyeInTheSky.SDK.MessageHandler
      def handle_protocol_event(_data, state), do: {:continue, state}

      @impl EyeInTheSky.SDK.MessageHandler
      def on_clean_exit(state), do: {:complete, resolve_exit_session_id(state)}

      defoverridable on_session_id: 2,
                     resolve_exit_session_id: 1,
                     handle_protocol_event: 2,
                     on_clean_exit: 1
```

In `run_loop/3`, add a parser-dispatch clause (next to `:skip`):

```elixir
          {:protocol, data} ->
            case module.handle_protocol_event(data, state) do
              {:continue, new_state} ->
                run_loop(module, new_state, opts)

              {:halt, reason} ->
                send(caller_pid, {:claude_error, sdk_ref, reason})
                stop_and_unregister(sdk_ref)
                :ok
            end
```

Replace the exit-0 branch:

```elixir
      {:claude_exit, _cli_ref, 0} ->
        case module.on_clean_exit(state) do
          {:complete, final_session_id} ->
            send(caller_pid, {:claude_complete, sdk_ref, final_session_id})
            log_sdk_exit(final_session_id, 0, tel_prefix)

          {:error, reason} ->
            send(caller_pid, {:claude_error, sdk_ref, reason})
            log_sdk_exit(session_id, {:clean_exit_rejected, reason}, tel_prefix)
        end

        stop_and_unregister(sdk_ref)
        :ok
```

- [ ] **Step 4: Run new tests AND the existing Claude/Codex SDK suites**

```bash
mix test test/eye_in_the_sky/sdk/message_handler_extension_test.exs
mix test test/eye_in_the_sky/codex test/eye_in_the_sky/claude
```

Expected: all PASS — the extension must not change any existing test outcome.

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/sdk/message_handler.ex test/eye_in_the_sky/sdk/message_handler_extension_test.exs
git commit -m "feat(sdk): MessageHandler handle_protocol_event/2 + on_clean_exit/1 extension callbacks"
```

---

### Task 5: Pi.Parser

**Files:**
- Create: `lib/eye_in_the_sky/pi/parser.ex`
- Test: `test/eye_in_the_sky/pi/parser_test.exs`

**Interfaces:**
- Consumes: `EyeInTheSky.Claude.Message` constructors — `Message.text(content, delta)`, `Message.thinking(content, delta)`, `Message.tool_use(name, input, metadata \\ %{})`.
- Produces: `parse_stream_line/1` returning `{:ok, Message.t()} | {:protocol, map()} | {:result, map()} | {:error, term()} | :skip`. Harness events map:
  - `response` envelopes, `ready`, `tool_request`, `exit` → `{:protocol, decoded_map}` (SDK bookkeeping/sequencing)
  - `assistant_delta` → `Message.text(delta, true)`; `thinking_delta` → `Message.thinking(delta, true)`
  - `tool_update`/`tool_result` → `Message.tool_use(...)`
  - `turn_end` → `{:result, %{usage:, input_tokens:, output_tokens:, total_cost_usd:, duration_ms:}}`
  - `turn_error` → `{:protocol, map}` (SDK stashes the sticky error; NOT `{:error, ...}` because the loop's `{:error, ...}` path stops immediately and would drop the following `turn_end` usage)
  - `error` → `{:error, {:pi_error, message}}`
  - unknown types / malformed JSON / blank → `:skip` (logged at debug)

- [ ] **Step 1: Write the failing tests (fixtures inline)**

```elixir
defmodule EyeInTheSky.Pi.ParserTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Pi.Parser

  test "response envelope is a protocol event" do
    line = ~s({"id":"pi-1","type":"response","command":"initialize","success":true,"data":{"version":"0.74.0","protocolVersion":1}})
    assert {:protocol, %{"type" => "response", "id" => "pi-1", "success" => true}} =
             Parser.parse_stream_line(line)
  end

  test "ready is a protocol event" do
    line = ~s({"type":"ready","sessionId":"abc-123","sessionFile":"/x/y","model":"openrouter/qwen/qwen3-coder"})
    assert {:protocol, %{"type" => "ready", "sessionId" => "abc-123"}} = Parser.parse_stream_line(line)
  end

  test "assistant_delta becomes a delta text message" do
    assert {:ok, %Message{type: :text, content: "hel", delta: true}} =
             Parser.parse_stream_line(~s({"type":"assistant_delta","delta":"hel"}))
  end

  test "thinking_delta becomes a delta thinking message" do
    assert {:ok, %Message{type: :thinking, content: "hmm", delta: true}} =
             Parser.parse_stream_line(~s({"type":"thinking_delta","delta":"hmm"}))
  end

  test "tool_update start becomes a partial tool_use" do
    line = ~s({"type":"tool_update","phase":"start","toolCallId":"t1","toolName":"bash","args":{"command":"ls"}})
    assert {:ok, %Message{type: :tool_use, content: %{name: "bash", input: %{"command" => "ls"}}, metadata: %{partial: true, tool_call_id: "t1"}}} =
             Parser.parse_stream_line(line)
  end

  test "tool_result becomes a completed tool_use" do
    line = ~s({"type":"tool_result","toolCallId":"t1","toolName":"bash","result":"ok\\n","isError":false})
    assert {:ok, %Message{type: :tool_use, content: %{name: "bash", input: %{"result" => "ok\n", "isError" => false}}, metadata: %{tool_call_id: "t1"}}} =
             Parser.parse_stream_line(line)
  end

  test "turn_end becomes a result with usage" do
    line =
      ~s({"type":"turn_end","totalCostUsd":0.012,"durationMs":5400,"aggregate":{"inputTokens":100,"outputTokens":50,"cacheReadTokens":0,"cacheCreationTokens":0,"totalTokens":150}})

    assert {:result, data} = Parser.parse_stream_line(line)
    assert data.input_tokens == 100
    assert data.output_tokens == 50
    assert data.total_cost_usd == 0.012
    assert data.duration_ms == 5400
    assert data.usage["totalTokens"] == 150
  end

  test "turn_end without aggregate still yields a result" do
    assert {:result, data} = Parser.parse_stream_line(~s({"type":"turn_end"}))
    assert data.input_tokens == 0
  end

  test "turn_error is a protocol event (sticky-error handling is SDK's job)" do
    assert {:protocol, %{"type" => "turn_error", "error" => "rate limited"}} =
             Parser.parse_stream_line(~s({"type":"turn_error","error":"rate limited"}))
  end

  test "tool_request is a protocol event (SDK auto-denies in Phase 1)" do
    line = ~s({"type":"tool_request","requestId":"r1","toolCallId":"t2","kind":"commandExecution","input":{"command":"rm -rf /"}})
    assert {:protocol, %{"type" => "tool_request", "requestId" => "r1"}} = Parser.parse_stream_line(line)
  end

  test "exit event is a protocol event" do
    assert {:protocol, %{"type" => "exit"}} = Parser.parse_stream_line(~s({"type":"exit","error":"fatal"}))
  end

  test "top-level error event is an error" do
    assert {:error, {:pi_error, "bad things"}} = Parser.parse_stream_line(~s({"type":"error","error":"bad things"}))
  end

  test "unknown event types are skipped (forward compat)" do
    assert :skip = Parser.parse_stream_line(~s({"type":"telemetry_v9","payload":1}))
  end

  test "malformed json and blank lines are skipped" do
    assert :skip = Parser.parse_stream_line("not json {")
    assert :skip = Parser.parse_stream_line("   ")
  end

  test "compaction events become status text messages" do
    assert {:ok, %Message{type: :text}} = Parser.parse_stream_line(~s({"type":"compaction_start","reason":"context"}))
    assert {:ok, %Message{type: :text}} = Parser.parse_stream_line(~s({"type":"compaction_end","reason":"context","aborted":false,"willRetry":false}))
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/eye_in_the_sky/pi/parser_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule EyeInTheSky.Pi.Parser do
  @moduledoc """
  Parses ndjson lines from the Pi harness sidecar.

  Protocol reference: docs/superpowers/specs/2026-07-06-pi-integration-design.md §3.
  Request/response envelopes, `ready`, `tool_request`, `turn_error`, and `exit`
  surface as `{:protocol, map}` for Pi.SDK bookkeeping; streaming content maps
  to Claude.Message structs for the shared pipeline.
  """

  alias EyeInTheSky.Claude.Message
  require Logger

  @protocol_types ~w(response ready tool_request turn_error exit)

  @spec parse_stream_line(String.t()) ::
          {:ok, Message.t()} | {:protocol, map()} | {:result, map()} | {:error, term()} | :skip
  def parse_stream_line(line) when is_binary(line) do
    case String.trim(line) do
      "" ->
        :skip

      trimmed ->
        case Jason.decode(trimmed) do
          {:ok, json} -> parse_event(json)
          {:error, _} -> :skip
        end
    end
  end

  defp parse_event(%{"type" => type} = event) when type in @protocol_types, do: {:protocol, event}

  defp parse_event(%{"type" => "assistant_delta", "delta" => delta}) when is_binary(delta),
    do: {:ok, Message.text(delta, true)}

  defp parse_event(%{"type" => "thinking_delta", "delta" => delta}) when is_binary(delta),
    do: {:ok, Message.thinking(delta, true)}

  defp parse_event(%{"type" => "turn_start"}), do: :skip

  defp parse_event(%{"type" => "tool_update"} = event) do
    input = event["args"] || event["result"] || %{}

    {:ok,
     Message.tool_use(
       event["toolName"] || "tool",
       %{name: event["toolName"], input: input},
       %{partial: true, tool_call_id: event["toolCallId"], phase: event["phase"]}
     )}
  end

  defp parse_event(%{"type" => "tool_result"} = event) do
    {:ok,
     Message.tool_use(
       event["toolName"] || "tool",
       %{name: event["toolName"], input: %{"result" => event["result"], "isError" => event["isError"]}},
       %{tool_call_id: event["toolCallId"]}
     )}
  end

  defp parse_event(%{"type" => "turn_end"} = event) do
    aggregate = event["aggregate"] || %{}

    {:result,
     %{
       input_tokens: aggregate["inputTokens"] || 0,
       output_tokens: aggregate["outputTokens"] || 0,
       usage: aggregate,
       iteration: event["iteration"],
       total_cost_usd: event["totalCostUsd"],
       duration_ms: event["durationMs"],
       error: event["error"]
     }}
  end

  defp parse_event(%{"type" => "compaction_start"} = event),
    do: {:ok, Message.text("[compacting context: #{event["reason"]}]", false)}

  defp parse_event(%{"type" => "compaction_end"} = event) do
    status = if event["aborted"], do: "aborted", else: "done"
    {:ok, Message.text("[compaction #{status}]", false)}
  end

  defp parse_event(%{"type" => "error"} = event),
    do: {:error, {:pi_error, event["error"] || "unknown Pi error"}}

  defp parse_event(other) do
    Logger.debug("[Pi.Parser] Unhandled event type: #{inspect(other["type"])}")
    :skip
  end
end
```

Note: the tool_use content shape (`%{name:, input:}`) must match what `Message.tool_use/3` produces for the existing pipeline — check `Message.tool_use/3`'s implementation and mirror Codex's call convention (`Message.tool_use(name, input_map, metadata)`); adjust the test assertions to the actual struct shape if `tool_use/3` wraps differently. The invariant to preserve: name + input reach the UI, `partial: true` marks in-progress.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/eye_in_the_sky/pi/parser_test.exs`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/pi/parser.ex test/eye_in_the_sky/pi/parser_test.exs
git commit -m "feat(pi): ndjson parser mapping harness events to Message/protocol tuples"
```

---

### Task 6: Pi.CLI (transport)

**Files:**
- Create: `lib/eye_in_the_sky/pi/cli.ex`
- Test: `test/eye_in_the_sky/pi/cli_test.exs`

**Interfaces:**
- Consumes: `EyeInTheSky.CLI.Port.{spawn_handler/5, cancel_port/2, find_binary/2, clear_binary_cache/1, resolve_idle_timeout/2}`; `EyeInTheSky.Pi.session_dir/1`.
- Produces (used by Task 7):
  - `spawn_harness(opts) :: {:ok, port(), session_ref :: reference()} | {:error, term()}` — opts: `:caller` (handler pid), `:project_path`, `:session_ref`, `:turn_id`, EITS id opts (same keys as Codex).
  - `send_ndjson(port, map) :: :ok` — encodes + writes one line via `Port.command/2` (callable from any process; `Port.command` does not require port ownership).
  - `cancel(port) :: :ok` — transport kill only (delegates `CLI.Port.cancel_port/2`).
  - `build_env(opts) :: [{charlist, charlist}]` — **allowlist**, public for tests.
  - `resolve_harness_command() :: {:ok, {exe :: String.t(), args :: [String.t()]}} | {:error, term()}` — public for tests.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule EyeInTheSky.Pi.CLITest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi.CLI

  describe "build_env/1 (allowlist)" do
    test "never forwards provider credentials, even when set in server env" do
      System.put_env("OPENAI_API_KEY", "decoy-openai")
      System.put_env("ANTHROPIC_API_KEY", "decoy-anthropic")
      System.put_env("OPENROUTER_API_KEY", "decoy-openrouter")
      on_exit(fn ->
        Enum.each(~w(OPENAI_API_KEY ANTHROPIC_API_KEY OPENROUTER_API_KEY), &System.delete_env/1)
      end)

      env_keys = CLI.build_env([]) |> Enum.map(fn {k, _v} -> List.to_string(k) end)

      refute "OPENAI_API_KEY" in env_keys
      refute "ANTHROPIC_API_KEY" in env_keys
      refute "OPENROUTER_API_KEY" in env_keys
    end

    test "forwards allowlisted base vars and EITS opts" do
      env = CLI.build_env(eits_session_uuid: "u-1", eits_project_id: 1, turn_id: "turn-9")
      env_map = Map.new(env, fn {k, v} -> {List.to_string(k), List.to_string(v)} end)

      assert env_map["HOME"] == System.get_env("HOME")
      assert env_map["PATH"] == System.get_env("PATH")
      assert env_map["EITS_SESSION_UUID"] == "u-1"
      assert env_map["EITS_PROJECT_ID"] == "1"
      assert env_map["EITS_PI_TURN_ID"] == "turn-9"
      assert Map.has_key?(env_map, "PI_PACKAGE_DIR")
    end
  end

  describe "resolve_harness_command/0" do
    test "EITS_PI_HARNESS override wins" do
      System.put_env("EITS_PI_HARNESS", "/tmp/fake-harness")
      on_exit(fn -> System.delete_env("EITS_PI_HARNESS") end)
      assert {:ok, {"/tmp/fake-harness", []}} = CLI.resolve_harness_command()
    end

    test "falls back to bun + source when compiled binary is absent" do
      System.delete_env("EITS_PI_HARNESS")

      case CLI.resolve_harness_command() do
        {:ok, {exe, args}} ->
          assert String.ends_with?(exe, "eits-pi-harness") or String.contains?(exe, "bun")
          if String.contains?(exe, "bun"), do: assert(["#{File.cwd!()}/pi-harness/src/main.ts"] == args)

        {:error, reason} ->
          assert reason == {:pi_harness_not_found, hint: "run scripts/build-pi-harness.sh"}
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/eye_in_the_sky/pi/cli_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule EyeInTheSky.Pi.CLI do
  @moduledoc """
  Transport for the Pi harness sidecar. Transport ONLY:
  opens the Port, writes encoded ndjson, and kills the OS process.
  Request ids, preamble sequencing, and the protocol verbs abort/dispose
  are owned by EyeInTheSky.Pi.SDK.

  Unlike Claude/Codex, stdin stays OPEN for the turn's lifetime — the SDK
  writes requests to it. Emits the shared legacy wire tags
  {:claude_output, ref, line} / {:claude_exit, ref, code} (intentional shim).
  """

  require Logger

  @default_idle_timeout_ms :infinity

  @doc """
  Opens a Port on the harness. Sends nothing — the SDK drives the preamble.

  Opts: :caller (handler pid), :session_ref, :project_path, :turn_id,
  plus eits_* id opts (same keys as Codex.CLI).
  """
  @spec spawn_harness(keyword()) :: {:ok, port(), reference()} | {:error, term()}
  def spawn_harness(opts \\ []) do
    project_path = opts |> Keyword.get(:project_path, File.cwd!()) |> Path.expand()

    with true <- File.dir?(project_path) || {:error, {:invalid_project_path, project_path}},
         {:ok, {exe, args}} <- resolve_harness_command() do
      caller = Keyword.get(opts, :caller, self())
      session_ref = Keyword.get(opts, :session_ref, make_ref())
      idle_timeout_ms = EyeInTheSky.CLI.Port.resolve_idle_timeout(opts, @default_idle_timeout_ms)

      Logger.info("[Pi.CLI] Spawning harness in #{project_path}: #{exe} #{Enum.join(args, " ")}")

      port =
        Port.open(
          {:spawn_executable, exe},
          [
            :binary,
            :exit_status,
            :use_stdio,
            :stderr_to_stdout,
            {:args, args},
            {:cd, project_path},
            {:env, build_env(opts)}
          ]
        )

      EyeInTheSky.CLI.Port.spawn_handler(port, session_ref, caller, idle_timeout_ms,
        telemetry_prefix: [:eits, :pi, :cli],
        log_prefix: "Pi.CLI"
      )

      :telemetry.execute([:eits, :pi, :cli, :spawn], %{system_time: System.system_time()}, %{
        project_path: project_path
      })

      {:ok, port, session_ref}
    end
  end

  @doc "Encode and write one ndjson request line. Callable from any process."
  @spec send_ndjson(port(), map()) :: :ok | {:error, :port_closed}
  def send_ndjson(port, map) when is_port(port) and is_map(map) do
    Port.command(port, Jason.encode!(map) <> "\n")
    :ok
  rescue
    ArgumentError -> {:error, :port_closed}
  end

  @doc "Transport-level kill (SIGTERM group -> SIGKILL). No protocol semantics."
  @spec cancel(port()) :: :ok
  def cancel(port) when is_port(port), do: EyeInTheSky.CLI.Port.cancel_port(port, "Pi.CLI")

  # -- Harness resolution ------------------------------------------------------

  @doc """
  EITS_PI_HARNESS override -> priv/bin/eits-pi-harness -> `bun pi-harness/src/main.ts`.
  """
  @spec resolve_harness_command() :: {:ok, {String.t(), [String.t()]}} | {:error, term()}
  def resolve_harness_command do
    override = System.get_env("EITS_PI_HARNESS")
    compiled = Path.expand("priv/bin/eits-pi-harness")
    source = Path.expand("pi-harness/src/main.ts")

    cond do
      override && override != "" -> {:ok, {override, []}}
      File.exists?(compiled) -> {:ok, {compiled, []}}
      File.exists?(source) && (bun = System.find_executable("bun")) -> {:ok, {bun, [source]}}
      true -> {:error, {:pi_harness_not_found, hint: "run scripts/build-pi-harness.sh"}}
    end
  end

  # -- Environment (ALLOWLIST — spec §4) ---------------------------------------

  @base_allowlist ~w(PATH HOME TMPDIR LANG)

  @doc """
  Allowlist env for the harness. Pi is multi-provider; a strip list would leak
  provider credentials (OPENAI_API_KEY, ...) into the sidecar. Credentials come
  from ~/.pi/agent/auth.json only.
  """
  @spec build_env(keyword()) :: [{charlist(), charlist()}]
  def build_env(opts) do
    base =
      for {key, value} <- System.get_env(),
          value != "",
          key in @base_allowlist or String.starts_with?(key, "LC_"),
          do: {String.to_charlist(key), String.to_charlist(value)}

    eits_pairs =
      [
        {"PI_PACKAGE_DIR", System.get_env("PI_PACKAGE_DIR") || Path.expand("priv/bin/pi")},
        {"EITS_PI_TURN_ID", opts[:turn_id]},
        {"EITS_SESSION_UUID", opts[:eits_session_uuid]},
        {"EITS_SESSION_ID", opts[:eits_session_id]},
        {"EITS_AGENT_UUID", opts[:eits_agent_uuid]},
        {"EITS_AGENT_ID", opts[:eits_agent_id]},
        {"EITS_PROJECT_ID", opts[:eits_project_id]},
        {"EITS_CHANNEL_ID", opts[:eits_channel_id]},
        {"EITS_MODEL", opts[:eits_model]},
        {"EITS_URL", opts[:eits_url] || System.get_env("EITS_URL", "http://localhost:5001/api/v1")}
      ]

    Enum.reduce(eits_pairs, base, fn {k, v}, acc ->
      EyeInTheSky.CLI.Port.maybe_add_env(acc, k, v)
    end)
  end
end
```

Note: `maybe_add_env` expects string-able values — verify it `to_string/1`s integers (check `lib/eye_in_the_sky/cli/port.ex:308`); if it doesn't, wrap values with `to_string/1` in the pairs list above.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/eye_in_the_sky/pi/cli_test.exs`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/pi/cli.ex test/eye_in_the_sky/pi/cli_test.exs
git commit -m "feat(pi): transport-only CLI (port spawn, ndjson writes, allowlist env)"
```

---

### Task 7: Pi.SDK

**Files:**
- Create: `lib/eye_in_the_sky/pi/sdk.ex`
- Test: `test/eye_in_the_sky/pi/sdk_test.exs`

**Interfaces:**
- Consumes: `Pi.CLI.spawn_harness/1`, `Pi.CLI.send_ndjson/2`, `Pi.CLI.cancel/1`; `EyeInTheSky.Pi.session_dir/1`; MessageHandler callbacks from Task 4; `EyeInTheSky.Claude.SDK.Registry`; `Utils.pi_cli_module/0` (Task 8 adds it — until then use `Application.get_env(:eye_in_the_sky, :pi_cli_module, EyeInTheSky.Pi.CLI)` inline).
- Produces (used by Task 8):
  - `start(prompt, opts) :: {:ok, ref, handler_pid} | {:error, term}` and `resume(session_id, prompt, opts)` (identical internals). Required opts: `:to`, `:session_id` (EITS session uuid — names the sessionDir), `:model`, `:project_path`. Optional: `:allowed_tools` (default `["*"]`), `:custom_instructions`, eits_* ids.
  - `cancel(ref)` — protocol abort → 3 s grace → transport kill.
  - Emits to caller: `{:claude_message, ref, %Message{}}`, `{:claude_complete, ref, session_id}`, `{:claude_error, ref, reason}` (legacy tags).

**Design (mirrors Codex.SDK's process shape):** the handler Task owns all protocol state. `start/2` spawns the handler, spawns the harness with `caller: handler_pid`, registers `ref → port`, then sends `{:start_handling, ref, port, preamble}`. The handler writes `initialize` first and runs a phase state machine inside `handle_protocol_event/2`:

```
:initializing --init response ok + version match--> send start_session --> :starting
:starting     --start_session response ok AND ready seen (either order)--> send prompt --> :streaming
:streaming    --{:result, data} (turn_end)--> handle_result: dispose, complete/fail
any phase     --failed response envelope--> {:halt, {:pi_preamble_failed, command, error}}
```

State fields: `phase`, `port`, `turn_end_seen` (bool), `pending` (`%{id => command}`), `next_id` (int), `sticky_error` (nil | binary), `ready_seen` (bool), `start_session_acked` (bool), `terminal` (nil — the exactly-once guard; `handle_result`/`on_clean_exit`/`{:halt, _}` paths each check it), plus the standard `sdk_ref`/`caller_pid`/`session_id`/`eits_session_id`.

Key behaviors to implement (each is a test below):

1. `on_clean_exit`: `{:complete, sid}` iff `turn_end_seen` and no `sticky_error`; else `{:error, :exit_before_turn_end}` / `{:error, {:pi_turn_error, msg}}`.
2. `turn_error` protocol event sets `sticky_error`; `handle_result` (turn_end) with `sticky_error` set emits `{:claude_error, ref, {:pi_turn_error, msg}}` (usage still logged) — not complete.
3. `tool_request` protocol event → immediately `send_ndjson(port, %{id: next_id, type: "deny_tool", requestId: req_id})` + emit a status text Message ("Pi requested tool approval — approvals are not enabled; denied (configure bypassPermissions)").
4. `handle_result` happy path: mark `terminal: :completed`, emit result Message (usage metadata: input/output tokens, `total_cost_usd`, `duration_ms`), emit `{:claude_complete, ref, eits_session_id}`, best-effort `send_ndjson(port, %{id: ..., type: "dispose"})`, then `MessageHandler.finalize_after_terminal_event/3` (its existing 2 s exit-wait + force-close covers the dispose-timeout kill).
5. Response envelope with unknown id → log warning, `{:continue, state}` (no crash).
6. `cancel/1`: look up port in Registry; `send_ndjson(port, %{id: "pi-cancel", type: "abort"})`; spawn a `Task` that sleeps 3 000 ms then calls `Pi.CLI.cancel(port)` if `Port.info(port) != nil`.
7. `initialize` response with `data.protocolVersion != 1` → `{:halt, {:pi_protocol_version_mismatch, got}}`.

- [ ] **Step 1: Write the failing tests** — drive the handler directly through `MessageHandler.run_loop/3` with a stub CLI module registered via `Application.put_env(:eye_in_the_sky, :pi_cli_module, StubCLI)`. The StubCLI records `send_ndjson` calls into a test-owned Agent and returns `:ok`; "port" is a `spawn(fn -> receive do: (:never -> :ok) end)` pid stand-in only where a real port isn't needed (Registry accepts pids). Feed lines by sending `{:claude_output, cli_ref, line}` to the handler pid, exits via `{:claude_exit, cli_ref, code}`. Cover, at minimum:

```
test "preamble ordering: initialize -> start_session (after init ok) -> prompt (after ack+ready, either order)"
test "ready before start_session response still gates prompt on both"
test "protocol version mismatch halts with claude_error"
test "failed initialize/start_session/prompt envelope halts with pi_preamble_failed"
test "exit 0 before turn_end -> claude_error :exit_before_turn_end"
test "exit nonzero before turn_end -> claude_error"
test "turn_end then exit 0 -> claude_complete with eits session id"
test "turn_error then turn_end -> claude_error {:pi_turn_error, msg} (sticky)"
test "turn_error then exit (no turn_end) -> claude_error"
test "assistant_delta lines emit {:claude_message, ref, %Message{delta: true}}"
test "unexpected tool_request is auto-denied (deny_tool written) and stream continues"
test "duplicate terminal: turn_end then error event -> exactly one terminal message to caller"
test "unknown response id -> logged, loop continues"
test "malformed line mid-stream -> skipped, loop continues"
```

Write each as a real ExUnit test following the Task 4 harness pattern (spawn `MessageHandler.run_loop(Pi.SDK, state, Pi.SDK.loop_opts())` with a hand-built state — expose `Pi.SDK.initial_state/3` and `Pi.SDK.loop_opts/0` as public functions so tests construct exactly what the handler process uses).

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/eye_in_the_sky/pi/sdk_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement `Pi.SDK`** — full module. Skeleton with all required pieces (implementer fills bodies to satisfy the tests; every clause listed here must exist):

```elixir
defmodule EyeInTheSky.Pi.SDK do
  @moduledoc """
  EITS MessageHandler adapter for the Pi harness (NOT the upstream Pi SDK).
  Owns request ids, pending-request bookkeeping, preamble sequencing, and
  the protocol verbs abort/dispose. Transport lives in Pi.CLI.
  """

  use EyeInTheSky.SDK.MessageHandler

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Claude.SDK.Registry
  alias EyeInTheSky.SDK.MessageHandler

  require Logger

  @protocol_version 1
  @cancel_grace_ms 3_000

  def loop_opts,
    do: [
      parser: EyeInTheSky.Pi.Parser,
      telemetry_prefix: [:eits, :pi, :sdk],
      log_raw_key: "log_pi_raw",
      log_raw_prefix: "pi.raw"
    ]

  def cli_module,
    do: Application.get_env(:eye_in_the_sky, :pi_cli_module, EyeInTheSky.Pi.CLI)

  # -- Public API (same contract as Codex.SDK) --------------------------------

  def start(prompt, opts \\ []), do: run_session(prompt, opts)
  # Resume is identical: the sessionDir (keyed by :session_id) carries continuity.
  def resume(_session_id, prompt, opts \\ []), do: run_session(prompt, opts)

  def cancel(ref) do
    case Registry.lookup(ref) do
      nil -> {:error, :not_found}
      port when is_port(port) ->
        cli_module().send_ndjson(port, %{id: "pi-cancel", type: "abort"})
        Task.start(fn ->
          Process.sleep(@cancel_grace_ms)
          if Port.info(port), do: cli_module().cancel(port)
        end)
        :ok
      pid when is_pid(pid) ->
        send(pid, :cancel)
        :ok
    end
  end

  # -- Session bootstrap -------------------------------------------------------
  # run_session/2: build initial_state, spawn handler Task (Codex.SDK pattern,
  # Task.Supervisor.start_child + Process.monitor(caller)), call
  # cli_module().spawn_harness(caller: handler_pid, ...), Registry.register(ref, port),
  # send {:start_handling, ref, port} to handler. Handler then writes the
  # initialize request and enters MessageHandler.run_loop(__MODULE__, state, loop_opts()).

  def initial_state(sdk_ref, caller_pid, opts) do
    %{
      sdk_ref: sdk_ref,
      caller_pid: caller_pid,
      session_id: opts[:session_id],
      eits_session_id: opts[:session_id],
      phase: :initializing,
      port: nil,
      pending: %{},
      next_id: 1,
      turn_end_seen: false,
      sticky_error: nil,
      ready_seen: false,
      start_session_acked: false,
      terminal: nil,
      prompt: opts[:prompt],
      start_session_payload: start_session_payload(opts)
    }
  end

  defp start_session_payload(opts) do
    %{
      type: "start_session",
      cwd: opts[:project_path] || File.cwd!(),
      sessionId: opts[:session_id],
      sessionDir: EyeInTheSky.Pi.session_dir(opts[:session_id]),
      model: opts[:model],
      allowedTools: opts[:allowed_tools] || ["*"],
      customInstructions: opts[:custom_instructions]
    }
  end

  # send_request/3: assigns "pi-<next_id>", stores pending[id] = command,
  # calls cli_module().send_ndjson(state.port, Map.put(payload, :id, id)),
  # returns bumped state.

  # -- MessageHandler callbacks ------------------------------------------------
  # handle_message/2: forward %Message{} to caller as {:claude_message, ref, msg}.
  # handle_protocol_event/2 clauses, in order:
  #   response envelope -> pop pending[id]; unknown id -> warn + continue;
  #     success=false -> {:halt, {:pi_preamble_failed, command, error}} when phase != :streaming,
  #                      else set sticky_error and continue;
  #     success=true  -> advance_phase(command, data, state)
  #   "ready"        -> ready_seen: true; advance_phase("ready", nil, state)
  #   "turn_error"   -> %{state | sticky_error: event["error"]}
  #   "tool_request" -> write deny_tool, emit status Message, continue
  #   "exit"         -> stash as sticky_error if no turn_end yet; continue (port exit is authoritative)
  # advance_phase: :initializing + init ok (verify data["protocolVersion"] == 1,
  #   else {:halt, {:pi_protocol_version_mismatch, v}}) -> send start_session -> :starting
  #   :starting + start_session_acked && ready_seen -> send prompt -> :streaming
  # handle_result/2 (turn_end): if state.terminal, do: :ok (exactly-once), else:
  #   sticky_error? -> claude_error {:pi_turn_error, msg}; else result Message
  #   (metadata: usage/total_cost_usd/duration_ms) + claude_complete with
  #   eits_session_id. Then best-effort dispose via send_request and
  #   MessageHandler.finalize_after_terminal_event(ref, sid, loop_opts()).
  # on_clean_exit/1: turn_end_seen && !sticky_error -> {:complete, eits_session_id};
  #   sticky_error -> {:error, {:pi_turn_error, sticky_error}};
  #   else {:error, :exit_before_turn_end}.
end
```

The implementer writes the full bodies (the tests define exact observable behavior). Keep every state transition in `Pi.SDK`; nothing protocol-shaped goes in `Pi.CLI`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/eye_in_the_sky/pi/sdk_test.exs`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/pi/sdk.ex test/eye_in_the_sky/pi/sdk_test.exs
git commit -m "feat(pi): SDK protocol layer (preamble sequencing, sticky errors, exactly-once terminal)"
```

---

### Task 8: Provider strategy + seams

**Files:**
- Create: `lib/eye_in_the_sky/claude/provider_strategy/pi.ex`
- Modify: `lib/eye_in_the_sky/claude/provider_strategy.ex:45` (add dispatch clause)
- Modify: `lib/eye_in_the_sky/claude/utils.ex` (add `pi_cli_module/0`)
- Modify: `lib/eye_in_the_sky/agents/agent_manager/record_builder.ex` (`resolve_provider/1`, `resolve_provider_conversation_id/2`)
- Test: `test/eye_in_the_sky/claude/provider_strategy_pi_test.exs`

**Interfaces:**
- Consumes: `Pi.SDK.start/2`, `Pi.SDK.resume/3`, `Pi.SDK.cancel/1` (Task 7 signatures).
- Produces: `ProviderStrategy.for_provider("pi") == EyeInTheSky.Claude.ProviderStrategy.Pi`; sessions created with `agent_type: "pi"` get `provider: "pi"` and a **pre-generated** conversation id (Claude-style — we name the sessionDir).

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule EyeInTheSky.Claude.ProviderStrategyPiTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Claude.ProviderStrategy

  test "for_provider dispatches pi" do
    assert ProviderStrategy.for_provider("pi") == EyeInTheSky.Claude.ProviderStrategy.Pi
  end

  test "for_provider default unchanged" do
    assert ProviderStrategy.for_provider("claude") == EyeInTheSky.Claude.ProviderStrategy.Claude
    assert ProviderStrategy.for_provider("codex") == EyeInTheSky.Claude.ProviderStrategy.Codex
  end

  test "pi strategy builds opts with session dir keyed by conversation id and bypass tools" do
    state = %{
      provider_conversation_id: "conv-uuid-1",
      project_path: "/tmp",
      eits_session_uuid: "sess-uuid",
      session_id: 42,
      agent_id: 7,
      project_id: 1
    }

    opts = EyeInTheSky.Claude.ProviderStrategy.Pi.build_opts(state, %{model: "openrouter/qwen/qwen3-coder"})

    assert opts[:session_id] == "conv-uuid-1"
    assert opts[:model] == "openrouter/qwen/qwen3-coder"
    assert opts[:allowed_tools] == ["*"]
    assert opts[:project_path] == "/tmp"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/eye_in_the_sky/claude/provider_strategy_pi_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement**

`provider_strategy.ex` — insert above the catch-all:

```elixir
  def for_provider("codex"), do: EyeInTheSky.Claude.ProviderStrategy.Codex
  def for_provider("pi"), do: EyeInTheSky.Claude.ProviderStrategy.Pi
  def for_provider(_), do: EyeInTheSky.Claude.ProviderStrategy.Claude
```

`utils.ex` — after `codex_cli_module/0`:

```elixir
  @doc """
  Returns the configured Pi CLI module (real or mock for tests).
  """
  @spec pi_cli_module() :: module()
  def pi_cli_module do
    Application.get_env(:eye_in_the_sky, :pi_cli_module, EyeInTheSky.Pi.CLI)
  end
```

(Then switch `Pi.SDK.cli_module/0` from Task 7 to delegate to `Utils.pi_cli_module/0`.)

`record_builder.ex`:

```elixir
  defp resolve_provider(opts) do
    case opts[:agent_type] do
      "codex" -> "codex"
      "gemini" -> "gemini"
      "pi" -> "pi"
      _ -> "claude"
    end
  end
```

The conversation-id function needs no code change — `"pi"` is not in the `["codex", "gemini"]` null list, so it pre-generates a UUID (Claude-style), which is exactly what Pi needs. Update the comment to say so:

```elixir
    # For codex and gemini sessions, leave uuid null — native session_id arrives later.
    # For claude AND pi sessions, pre-generate: Claude passes it as --session-id;
    # Pi uses it to name the persistent sessionDir (we own the id).
```

New `provider_strategy/pi.ex`:

```elixir
defmodule EyeInTheSky.Claude.ProviderStrategy.Pi do
  @moduledoc """
  ProviderStrategy implementation for the Pi harness provider.
  Phase 1: bypass approval mode only (allowedTools: ["*"]).
  """

  @behaviour EyeInTheSky.Claude.ProviderStrategy

  alias EyeInTheSky.Claude.ProviderStrategy
  alias EyeInTheSky.Pi

  require Logger

  @impl true
  def format_content(block), do: ProviderStrategy.format_content_default(block)

  @impl true
  def start(state, job) do
    opts = build_opts(state, job.context)
    warn_content_blocks(job.content_blocks)
    Logger.info("Starting new Pi session #{state.provider_conversation_id}")
    Pi.SDK.start(job.message, opts)
  end

  @impl true
  def resume(state, job) do
    opts = build_opts(state, job.context)
    warn_content_blocks(job.content_blocks)
    Logger.info("Resuming Pi session #{state.provider_conversation_id}")
    Pi.SDK.resume(state.provider_conversation_id, job.message, opts)
  end

  @impl true
  def cancel(ref), do: Pi.SDK.cancel(ref)

  @doc false
  def build_opts(state, context) do
    [
      to: self(),
      model: context[:model],
      session_id: state.provider_conversation_id,
      project_path: state.project_path,
      allowed_tools: ["*"],
      custom_instructions: eits_custom_instructions(state, context),
      eits_session_uuid: state.eits_session_uuid,
      eits_session_id: state.session_id,
      eits_agent_uuid: state.agent_id,
      eits_agent_id: state.agent_id,
      eits_project_id: state.project_id,
      eits_channel_id: context[:channel_id],
      eits_model: context[:model],
      eits_url: System.get_env("EITS_URL", "http://localhost:5001/api/v1")
    ]
  end

  defp eits_custom_instructions(state, context) do
    if (context[:eits_workflow] || "1") != "0" do
      EyeInTheSky.Codex.SDK.eits_init_prompt(state)
      |> String.replace("--provider codex", "--provider pi")
    else
      nil
    end
  end

  defp warn_content_blocks([]), do: :ok

  defp warn_content_blocks(blocks) when is_list(blocks) do
    Logger.warning("[Pi] Stripping #{length(blocks)} content block(s): Pi Phase 1 is text-only")
  end
end
```

Note on `stream_assembler_for/1` (`agent_worker.ex:564`): Pi is delta-based like Claude, and the default clause already returns `StreamAssembler.new()` — no code change. Add a comment on the default clause: `# "pi" intentionally uses the default (delta-based) assembler.`

- [ ] **Step 4: Run tests + full compile**

```bash
mix test test/eye_in_the_sky/claude/provider_strategy_pi_test.exs
mix compile --warnings-as-errors
```

Expected: PASS, clean compile.

- [ ] **Step 5: Commit**

```bash
git add lib/eye_in_the_sky/claude/provider_strategy/pi.ex lib/eye_in_the_sky/claude/provider_strategy.ex lib/eye_in_the_sky/claude/utils.ex lib/eye_in_the_sky/agents/agent_manager/record_builder.ex lib/eye_in_the_sky/claude/agent_worker.ex lib/eye_in_the_sky/pi/sdk.ex test/eye_in_the_sky/claude/provider_strategy_pi_test.exs
git commit -m "feat(pi): provider strategy, dispatch seam, record builder, cli module seam"
```

---

### Task 9: Model validation + UI metadata

**Files:**
- Modify: `lib/eye_in_the_sky/agents/model_config.ex`
- Modify: `lib/eye_in_the_sky/agents/spawn_validator.ex:97-115` (`validate_provider_model/2`), `:39-40` (`default_model_for_provider/1`)
- Modify: `lib/eye_in_the_sky_web/components/dm_helpers.ex:159-174`
- Test: `test/eye_in_the_sky/agents/model_config_pi_test.exs`

**Interfaces:**
- Produces: `ModelConfig.valid_model?("pi", model) :: boolean` (format regex); `ModelConfig.valid_model?(other, model)` (list membership, unchanged semantics); `ModelConfig.default_model("pi") == nil`; `ModelConfig.pi_split_model!("prov/mod/el") == {"prov", "mod/el"}`; spawn validator accepts `provider="pi"` with explicit format-valid model, rejects missing model with a settings-directed message.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule EyeInTheSky.Agents.ModelConfigPiTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Agents.{ModelConfig, SpawnValidator}

  test "pi model format validation" do
    assert ModelConfig.valid_model?("pi", "google/gemini-2.5-pro")
    assert ModelConfig.valid_model?("pi", "openrouter/qwen/qwen3-coder")
    assert ModelConfig.valid_model?("pi", "openrouter/anthropic/claude-3.5-sonnet@beta")
    refute ModelConfig.valid_model?("pi", "no-slash")
    refute ModelConfig.valid_model?("pi", "has space/model")
    refute ModelConfig.valid_model?("pi", nil)
  end

  test "non-pi providers keep list-based validation" do
    assert ModelConfig.valid_model?("codex", "gpt-5.5")
    refute ModelConfig.valid_model?("codex", "made-up")
  end

  test "default_model for pi is nil (resolved from discovery in Phase 2)" do
    assert ModelConfig.default_model("pi") == nil
  end

  test "pi_split_model! splits on the FIRST slash only" do
    assert ModelConfig.pi_split_model!("openrouter/qwen/qwen3-coder") == {"openrouter", "qwen/qwen3-coder"}
  end

  test "spawn validator accepts pi with explicit model" do
    assert {:ok, params} =
             SpawnValidator.validate(%{
               "instructions" => "do the thing",
               "provider" => "pi",
               "model" => "google/gemini-2.5-pro"
             })

    assert params["provider"] == "pi"
  end

  test "spawn validator rejects pi without a model, pointing at settings" do
    assert {:error, "invalid_model", message} =
             SpawnValidator.validate(%{"instructions" => "x", "provider" => "pi"})

    assert message =~ "pi"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/eye_in_the_sky/agents/model_config_pi_test.exs`
Expected: FAIL — `valid_model?/2` undefined.

- [ ] **Step 3: Implement**

`model_config.ex` additions:

```elixir
  # Pi models are format-validated ("<pi-provider>/<model-id>"); the true list
  # comes from Pi model discovery (Phase 2). Model id may itself contain "/".
  @pi_model_regex ~r{^[A-Za-z0-9_.-]+/[A-Za-z0-9_.:/@+-]+$}

  def default_model("codex"), do: "gpt-5.5"
  def default_model("pi"), do: nil

  @doc "Validates a model for a provider: format-based for pi, list-based otherwise."
  def valid_model?("pi", model) when is_binary(model), do: Regex.match?(@pi_model_regex, model)
  def valid_model?("pi", _), do: false
  def valid_model?(provider, model), do: model in valid_model_slugs(provider)

  @doc "Splits a pi model into {pi_provider, model_id} on the FIRST slash only."
  def pi_split_model!(model) when is_binary(model) do
    [provider, model_id] = String.split(model, "/", parts: 2)
    {provider, model_id}
  end

  def valid_model_combos do
    %{
      "claude" => valid_model_slugs("claude"),
      "codex" => valid_model_slugs("codex"),
      "pi" => :format_validated
    }
  end
```

`spawn_validator.ex` — replace `validate_provider_model/2` (its only consumer of the combos values) and the pi default:

```elixir
  defp default_model_for_provider("codex"), do: ModelConfig.default_model("codex")
  defp default_model_for_provider("pi"), do: nil
  defp default_model_for_provider(_), do: "haiku"

  defp validate_provider_model(provider, model) do
    combos = ModelConfig.valid_model_combos()

    cond do
      not Map.has_key?(combos, provider) ->
        valid_providers = combos |> Map.keys() |> Enum.join(", ")
        {:error, "invalid_provider", "invalid provider '#{provider}'; must be one of: #{valid_providers}"}

      provider == "pi" and is_nil(model) ->
        {:error, "invalid_model",
         "provider 'pi' requires an explicit model (format '<pi-provider>/<model-id>'); configure providers in ~/.pi/agent/auth.json"}

      ModelConfig.valid_model?(provider, model) ->
        {:ok, {provider, model}}

      true ->
        {:error, "invalid_model", invalid_model_message(provider, model)}
    end
  end

  defp invalid_model_message("pi", model),
    do: "invalid pi model '#{model}'; expected format '<pi-provider>/<model-id>' (e.g. google/gemini-2.5-pro)"

  defp invalid_model_message(provider, model) do
    valid = ModelConfig.valid_model_slugs(provider) |> Enum.join(", ")
    "invalid model '#{model}' for provider '#{provider}'; must be one of: #{valid}"
  end
```

Grep for other `valid_model_combos` consumers before committing (`grep -rn "valid_model_combos" lib/ test/`) — any consumer that iterates the values as lists must be updated to skip/handle `:format_validated`.

`dm_helpers.ex` — add clauses next to the existing codex/claude ones (match the existing function shapes exactly — read lines 159-174 first):

```elixir
  def provider_icon("pi"), do: existing-shape-with-"pi"-asset-or-fallback
  def provider_icon_class("pi"), do: "..."
  def stream_provider_label("pi"), do: "Pi"
```

Use the same fallback icon the module uses for unknown providers if no Pi logo asset exists yet (do not add binary assets in this task).

- [ ] **Step 4: Run tests to verify they pass**

```bash
mix test test/eye_in_the_sky/agents/model_config_pi_test.exs
mix test test/eye_in_the_sky/agents/  # existing validator tests must stay green
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/agents/model_config.ex lib/eye_in_the_sky/agents/spawn_validator.ex lib/eye_in_the_sky_web/components/dm_helpers.ex test/eye_in_the_sky/agents/model_config_pi_test.exs
git commit -m "feat(pi): format-based model validation, spawn validator, provider UI labels"
```

---

### Task 10: scripts/eits --provider pi

**Files:**
- Modify: `scripts/eits` (~lines 1642, 1658-1667, 1720-1748 — provider help, valid models, local validation `case`; grep `--provider` in the file to find the current locations)

- [ ] **Step 1: Add pi to the validation case**

In the provider validation `case` (currently covering claude/codex/gemini), add:

```bash
    pi)
      # Format-validated: <pi-provider>/<model-id> (model id may contain '/')
      if [[ -z "$MODEL" ]]; then
        echo '{"error":"provider pi requires --model <pi-provider>/<model-id>","code":"invalid_model"}' >&2
        exit 2
      fi
      if [[ ! "$MODEL" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.:/@+-]+$ ]]; then
        echo "{\"error\":\"invalid pi model '$MODEL'; expected <pi-provider>/<model-id>\",\"code\":\"invalid_model\"}" >&2
        exit 2
      fi
      ;;
```

Update the `--provider` help text to mention `pi` and add a "Valid models (--provider pi)" help line: `any '<pi-provider>/<model-id>' (format-validated; requires --model)`.

- [ ] **Step 2: Verify manually**

```bash
scripts/eits agents spawn --provider pi --instructions "x" --dry-run
scripts/eits agents spawn --provider pi --model "google/gemini-2.5-pro" --instructions "x" --dry-run
scripts/eits agents spawn --provider pi --model "bad model" --instructions "x" --dry-run
```

Expected: first → invalid_model exit 2; second → prints the curl command with `"provider":"pi"`; third → invalid_model exit 2.

- [ ] **Step 3: Commit**

```bash
git add scripts/eits
git commit -m "feat(pi): scripts/eits --provider pi with format-based model validation"
```

---### Task 11: Lifecycle & protocol-ordering integration tests (scripted fake harness)

**Files:**
- Create: `test/support/fake_pi_harness.sh` (a shell script replaying a canned event stream, driven by a scenario file)
- Create: `test/eye_in_the_sky/pi/integration_test.exs`

**Interfaces:**
- Consumes: `EITS_PI_HARNESS` override (Task 6) — the test sets it to the fake script; `Pi.SDK.start/2` with `to: self()`.

- [ ] **Step 1: Write the fake harness**

```bash
#!/usr/bin/env bash
# Fake Pi harness: replays $FAKE_PI_SCENARIO (a file of output lines) while
# consuming stdin requests. Lines beginning with WAIT:<type> block until a
# request of that type arrives on stdin. Line EXIT:<code> exits.
set -u
scenario="${FAKE_PI_SCENARIO:?}"

declare -a seen_types=()

wait_for() {
  local want="$1"
  for t in "${seen_types[@]:-}"; do [[ "$t" == "$want" ]] && return 0; done
  while IFS= read -r req; do
    local t
    t=$(printf '%s' "$req" | sed -n 's/.*"type":"\([a-z_]*\)".*/\1/p')
    seen_types+=("$t")
    # auto-respond success to every request, echoing its id
    local id
    id=$(printf '%s' "$req" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
    if [[ -n "$id" ]]; then
      if [[ "$t" == "initialize" ]]; then
        printf '{"id":"%s","type":"response","command":"initialize","success":true,"data":{"version":"test","protocolVersion":1}}\n' "$id"
      else
        printf '{"id":"%s","type":"response","command":"%s","success":true,"data":true}\n' "$id" "$t"
      fi
    fi
    [[ "$t" == "$want" ]] && return 0
  done
}

while IFS= read -r line; do
  case "$line" in
    WAIT:*) wait_for "${line#WAIT:}" ;;
    EXIT:*) exit "${line#EXIT:}" ;;
    *) printf '%s\n' "$line" ;;
  esac
done < "$scenario"
# drain stdin until closed, then exit 0
cat >/dev/null
exit 0
```

`chmod +x test/support/fake_pi_harness.sh`.

- [ ] **Step 2: Write the integration tests**

Each test writes a scenario file into `@tag :tmp_dir`, sets `EITS_PI_HARNESS` to the fake script with `FAKE_PI_SCENARIO` in env (the fake reads it via `System.put_env` — since env allowlist strips custom vars, pass the scenario path via `EITS_PI_SESSION_ROOT`-style: add `FAKE_PI_SCENARIO` to the allowlist **in test env only** via a `Application.put_env(:eye_in_the_sky, :pi_test_env_extra, [...])` hook in `build_env`, OR simpler: generate a per-test wrapper script that hardcodes the scenario path and point `EITS_PI_HARNESS` at the wrapper). Use the wrapper-script approach — no production code changes:

```elixir
defp fake_harness!(tmp_dir, scenario_lines) do
  scenario = Path.join(tmp_dir, "scenario.txt")
  File.write!(scenario, Enum.join(scenario_lines, "\n") <> "\n")
  wrapper = Path.join(tmp_dir, "harness.sh")
  fake = Path.expand("test/support/fake_pi_harness.sh")
  File.write!(wrapper, "#!/bin/sh\nFAKE_PI_SCENARIO=#{scenario} exec #{fake}\n")
  File.chmod!(wrapper, 0o755)
  System.put_env("EITS_PI_HARNESS", wrapper)
  on_exit(fn -> System.delete_env("EITS_PI_HARNESS") end)
end
```

Scenarios to cover (each an ExUnit test asserting on `{:claude_message|:claude_complete|:claude_error, ref, ...}` received by the test process):

1. **Happy path:** `WAIT:start_session` → ready line → `WAIT:prompt` → `turn_start` → two `assistant_delta`s → `turn_end` → `WAIT:dispose` → `EXIT:0` ⇒ deltas received, then `{:claude_complete, ref, session_id}`.
2. **Ready before start_session response** (fake auto-responds after emitting ready — reorder lines) ⇒ still completes.
3. **exit 0 before turn_end:** `WAIT:prompt` → one delta → `EXIT:0` ⇒ `{:claude_error, ref, :exit_before_turn_end}`.
4. **exit 1 before turn_end** ⇒ `{:claude_error, ref, _}`.
5. **turn_error then turn_end** ⇒ `{:claude_error, ref, {:pi_turn_error, _}}`, no `:claude_complete`.
6. **malformed line mid-stream** (`this is not json`) between deltas ⇒ stream continues, completes.
7. **tool_request auto-deny:** emit `tool_request` after prompt, then `WAIT:deny_tool` → `turn_end` → `EXIT:0` ⇒ completes; the WAIT proves deny_tool was written.
8. **cancel:** scenario blocks (`WAIT:abort`) after first delta; test calls `Pi.SDK.cancel(ref)`; scenario then emits nothing (`EXIT:143` after WAIT) ⇒ error/canceled outcome, process gone.
9. **Serialization (AgentWorker-level):** start a Pi AgentWorker (or drive `Pi.SDK` twice) and send two prompts for one session; assert the second harness only spawns after the first exits (fake writes a pidfile; test asserts no overlap). If AgentWorker test scaffolding is too heavy here, assert at the SDK level that Registry holds at most one port per ref and add the worker-level test to the existing agent_worker test suite following its current patterns.

- [ ] **Step 3: Run**

Run: `mix test test/eye_in_the_sky/pi/integration_test.exs`
Expected: all scenarios PASS.

- [ ] **Step 4: Commit**

```bash
git add test/support/fake_pi_harness.sh test/eye_in_the_sky/pi/integration_test.exs
git commit -m "test(pi): lifecycle + protocol-ordering integration tests via scripted fake harness"
```

---

### Task 12: Harness sandbox smoke tests (bun test)

**Files:**
- Create: `pi-harness/test/sandbox.test.ts`

**Interfaces:**
- Consumes: the sandbox helpers in `pi-harness/src/main.ts` (`safePath` / `assertInsideWorkspace` / `assertWritableTarget` — export them from main.ts if not already exported; a pure re-export is an allowed vendoring edit).

- [ ] **Step 1: Write the tests**

```typescript
import { describe, expect, test } from "bun:test";
import { mkdtempSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
// Export these from main.ts (or a extracted sandbox.ts) as part of this task:
import { safeExistingPath, assertWritableTarget } from "../src/main";

describe("workspace sandbox (security invariant — spec §1)", () => {
  const ws = mkdtempSync(join(tmpdir(), "pi-ws-"));
  const outside = mkdtempSync(join(tmpdir(), "pi-outside-"));

  test("read outside workspace is denied", () => {
    writeFileSync(join(outside, "secret.txt"), "nope");
    expect(() => safeExistingPath(ws, join(outside, "secret.txt"))).toThrow(/escapes workspace/i);
  });

  test("write outside workspace is denied", () => {
    expect(() => assertWritableTarget(ws, join(outside, "evil.txt"))).toThrow(/escapes workspace/i);
  });

  test("symlink escape is denied", () => {
    const link = join(ws, "link-out");
    symlinkSync(outside, link);
    expect(() => assertWritableTarget(ws, join(link, "evil.txt"))).toThrow();
  });

  test("path inside workspace is allowed", () => {
    writeFileSync(join(ws, "ok.txt"), "fine");
    expect(safeExistingPath(ws, join(ws, "ok.txt"))).toContain(ws);
  });
});
```

Adapt import names/signatures to the actual helpers in the vendored source (check with `grep -n "assertInsideWorkspace\|safePath\|safeExistingPath\|assertWritableTarget" pi-harness/src/main.ts`) — the four behaviors above are the requirement, the function names are not.

- [ ] **Step 2: Run**

```bash
cd pi-harness && bun test && cd ..
```

Expected: 4 pass.

- [ ] **Step 3: Wire into build script** — add `bun test` after `bun run typecheck` in `scripts/build-pi-harness.sh`.

- [ ] **Step 4: Commit**

```bash
git add pi-harness scripts/build-pi-harness.sh
git commit -m "test(pi): harness workspace-sandbox smoke tests (read/write/symlink escape denied)"
```

---

### Task 13: Live-port transport smoke test

**Files:**
- Create: `test/eye_in_the_sky/pi/live_port_test.exs` (tagged `@moduletag :live_pi` — excluded by default, run explicitly)

**Purpose (spec §8, Codex watch item):** prove `Port.command/2` from a process that is NOT the port owner works for our topology (SDK writes; `CLI.Port.spawn_handler` handler owns the port), and that the compiled harness responds over a real BEAM port.

- [ ] **Step 1: Write the test**

```elixir
defmodule EyeInTheSky.Pi.LivePortTest do
  use ExUnit.Case, async: false
  @moduletag :live_pi

  alias EyeInTheSky.Pi.CLI

  setup do
    case CLI.resolve_harness_command() do
      {:ok, _} -> :ok
      {:error, _} -> raise "harness missing — run scripts/build-pi-harness.sh"
    end
  end

  test "initialize round-trip over a real port, written from a non-owner process" do
    parent = self()
    {:ok, port, _ref} = CLI.spawn_harness(caller: parent, project_path: System.tmp_dir!())

    # write from a DIFFERENT process than the handler that owns the port
    Task.async(fn ->
      :ok = CLI.send_ndjson(port, %{id: "pi-1", type: "initialize", protocolVersion: 1})
    end)
    |> Task.await()

    assert_receive {:claude_output, _ref, line}, 30_000
    assert %{"id" => "pi-1", "success" => true, "data" => %{"protocolVersion" => 1}} = Jason.decode!(line)

    CLI.cancel(port)
    assert_receive {:claude_exit, _ref, _code}, 10_000
  end
end
```

Add to `test/test_helper.exs` (if not already the pattern): `ExUnit.configure(exclude: [live_pi: true])` — check how existing excluded tags are handled first and follow that pattern.

- [ ] **Step 2: Run explicitly**

```bash
scripts/build-pi-harness.sh
mix test test/eye_in_the_sky/pi/live_port_test.exs --include live_pi
```

Expected: PASS. **If `Port.command` from the Task fails or output never arrives, STOP — the transport design needs a routing change (funnel writes through the handler process); raise this before continuing.**

- [ ] **Step 3: Commit**

```bash
git add test/eye_in_the_sky/pi/live_port_test.exs test/test_helper.exs
git commit -m "test(pi): live-port transport smoke test (non-owner Port.command, real harness)"
```

---

### Task 14: Resume-semantics validation + manual E2E

**Files:**
- Create: `docs/superpowers/specs/2026-07-06-pi-resume-validation.md` (findings record)

**Purpose:** the spec's Phase 1 gate — verify Pi transcript persistence under success/cancel/crash/repeated-resume before trusting `continueRecent`.

- [ ] **Step 1: Precondition** — at least one Pi provider configured: `test -f ~/.pi/agent/auth.json` (if absent, configure a cheap OpenRouter key with the terminal `pi` first; this is a manual step for the user).

- [ ] **Step 2: Scripted resume matrix (uses the real harness, one scenario per run)**

For each case, drive two sequential `Pi.SDK.start` calls (IEx or a `:live_pi`-tagged test) against the same `session_id` uuid with prompts "remember the word FLAMINGO" then "what word did I ask you to remember?":

1. resume after successful turn ⇒ second answer contains FLAMINGO.
2. resume after canceled turn (cancel mid-first-turn) ⇒ second turn starts cleanly (no crash, no corrupted-transcript error).
3. resume after killed harness (`kill -9` the OS pid mid-turn) ⇒ same.
4. repeated resume (3 turns) ⇒ transcript grows, `ls var/pi-sessions/<uuid>/` shows ONE transcript lineage (not one file per turn that `continueRecent` could mis-pick).

Record pass/fail + `ls -la` of the session dir per case in the findings doc. **If case 3 or 4 shows `continueRecent` picking a wrong/partial transcript, implement the spec's fallback (pin a stable transcript file in the harness `start_session`) before closing Phase 1.**

- [ ] **Step 3: Manual E2E through the app**

```bash
scripts/build-pi-harness.sh
PORT=5002 DISABLE_AUTH=true mix phx.server
scripts/eits agents spawn --provider pi --model "openrouter/<cheap-model>" \
  --instructions "Say hello, then run 'ls' and summarize. EITS_PROJECT_ID=1"
```

Verify in the UI at localhost:5002: streaming text appears, tool activity renders, session completes (status `idle`/`waiting`, not `failed`), usage/cost visible on the result, a second DM to the session resumes with context, cancel mid-turn stops it.

- [ ] **Step 4: Commit findings + close out**

```bash
git add docs/superpowers/specs/2026-07-06-pi-resume-validation.md
git commit -m "docs(pi): resume-semantics validation findings (Phase 1 gate)"
mix compile --warnings-as-errors && mix test
```

Expected: full suite green. Phase 1 exit criteria met: spawn, stream, resume, cancel from UI and CLI.

---

## Self-Review Notes (performed at write time)

- **Spec coverage:** invariants → Tasks 4/7/11; session root → 3; allowlist env → 6; protocol version → 1/7; auto-deny → 7/11; sandbox smoke → 12; live-port → 13; resume gate → 14; scripts/eits → 10; model split rule → 9 (`pi_split_model!`); `EITS_PI_TURN_ID` → 6 (build_env) — `ProviderStrategy.Pi.build_opts` passes no `:turn_id` yet; Task 8 implementer should add `turn_id: inspect(make_ref())` to `build_opts/2`. Discovery/settings/OAuth/approval-cards are Phase 2/3 — intentionally absent.
- **Known judgment call:** `turn_error` surfaces as `{:protocol, ...}` (not parser `{:error, ...}`) so the loop doesn't stop before `turn_end`'s usage arrives — this is the sticky-error design from the spec.
- **Type consistency:** `Pi.SDK.cancel/1` matches `ProviderStrategy` callback (`cancel(ref)`); `spawn_harness` returns `{:ok, port, ref}` like Codex `spawn_cli`; parser return set matches the extended MessageHandler contract from Task 4.
