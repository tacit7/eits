# Pi Integration Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** API-key management + model discovery for the Pi provider (spec Phase 2), plus two Phase-1 follow-ups: Pi error-category classification (spec §7) and inline provider-error rendering in chat.

**Architecture:** A `Pi.Control` module runs one-shot harness invocations (initialize → verb → response → exit) for `discover_models` / `list_providers` / `auth_status` / `set_api_key` / `clear_api_key`. A `ModelDiscoveryCache` GenServer+ETS (60 s TTL, invalidated on key changes, manual refresh) feeds the spawn drawer's new Pi optgroup and a new `/settings` "Providers" tab. Error work is provider-agnostic where possible: classifier gains Pi message-content mapping + a `:model_not_found` category; systemic failures persist a system message into the transcript (reusing the `on_spawn_error` precedent) so errors finally render in chat.

**Tech Stack:** Elixir/Phoenix LiveView, ETS+GenServer cache (codebase convention — no Cachex), DaisyUI, ExUnit.

## Global Constraints

- Credentials live ONLY in `~/.pi/agent/auth.json`, written by the harness via `set_api_key`/`clear_api_key` IPC. Never store keys in EITS `Settings`/`meta`/DB. Never log key material (no raw-payload logging on the set_api_key path).
- `Pi.CLI` stays transport-only; `Pi.Control` owns its own request ids (`"ctl-<n>"`) and response awaiting.
- Discovery failure must never crash or block the UI: render last cached list with a stale warning, else an error hint + free-text model entry (format-validated) still works.
- Model format/split rules unchanged: `~r{^[A-Za-z0-9_.-]+/[A-Za-z0-9_.:/@+-]+$}`, split with `String.split(model, "/", parts: 2)`.
- Existing Claude/Codex behavior must not change except where explicitly stated (system-error message on systemic failure is intentionally provider-wide).
- `mix compile --warnings-as-errors` before every commit. No AI attribution in commits. Work in worktrees off `features`.
- OAuth device-code flow is Phase 3 — do NOT implement `oauth_*` verbs.

## File Structure

```
lib/eye_in_the_sky/pi/control.ex                     # Task 1 (new)
lib/eye_in_the_sky/pi/model_discovery_cache.ex       # Task 2 (new)
lib/eye_in_the_sky/application.ex                    # Task 2 (child)
lib/eye_in_the_sky/claude/agent_worker/error_classifier.ex   # Task 3
lib/eye_in_the_sky_web/helpers/status_helpers.ex     # Task 3 (badge tier)
lib/eye_in_the_sky/agent_worker_events.ex            # Task 4 (system error msg + stream_error text)
lib/eye_in_the_sky_web/helpers/model_helpers.ex      # Task 5 (pi_models/0)
lib/eye_in_the_sky_web/components/new_agent_drawer.ex # Task 5
lib/eye_in_the_sky_web/live/overview_live/settings.ex # Task 6 (tab registration)
lib/eye_in_the_sky_web/live/overview_live/settings/providers_tab.ex # Task 6 (new)
test/eye_in_the_sky/pi/control_test.exs              # Task 1
test/eye_in_the_sky/pi/model_discovery_cache_test.exs # Task 2
test/eye_in_the_sky/claude/agent_worker/error_classifier_test.exs # Task 3 (extend)
test/eye_in_the_sky/agent_worker_events_error_message_test.exs    # Task 4
test/eye_in_the_sky_web/live/settings_providers_tab_test.exs      # Task 6
```

Dependency order: Task 1 → Task 2 → Tasks 5, 6. Tasks 3 and 4 are independent of 1/2 and of each other.

---

### Task 1: Pi.Control — one-shot harness IPC

**Files:**
- Create: `lib/eye_in_the_sky/pi/control.ex`
- Test: `test/eye_in_the_sky/pi/control_test.exs`

**Interfaces:**
- Consumes: `Utils.pi_cli_module/0` → module with `spawn_harness/1`, `send_ndjson/2`, `cancel/1` (Phase 1 signatures: `spawn_harness(opts) :: {:ok, port, ref}`; output arrives as `{:claude_output, ref, line}` / `{:claude_exit, ref, code}` to the `:caller`).
- Produces (Tasks 2/6 rely on these exact shapes):
  - `discover_models/0 :: {:ok, [map]} | {:error, term}` — each map is the raw harness model (`"id"`, `"provider"`, `"modelId"`, `"label"`, `"contextWindowTokens"`, `"authSource"`).
  - `list_providers/0 :: {:ok, %{"defaultVisibleCount" => int, "providers" => [map]}} | {:error, term}`
  - `auth_status/0 :: {:ok, map} | {:error, term}`
  - `set_api_key(provider_id :: String.t(), key :: String.t()) :: :ok | {:error, term}`
  - `clear_api_key(provider_id :: String.t()) :: :ok | {:error, term}`

- [ ] **Step 1: Write the failing test** — use a StubCLI (same pattern as `test/eye_in_the_sky/pi/sdk_test.exs`) whose `spawn_harness` returns a fake ref and whose test feeds `{:claude_output, ref, line}` into the calling process:

```elixir
defmodule EyeInTheSky.Pi.ControlTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi.Control

  defmodule StubCLI do
    # The test process itself is the :caller, so feed/2 sends straight to it.
    def start_link, do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def sends, do: Agent.get(__MODULE__, & &1) |> Enum.reverse()

    def spawn_harness(opts) do
      send(self(), {:harness_spawned, opts[:caller]})
      {:ok, spawn(fn -> receive do: (:never -> :ok) end), make_ref()}
    end

    def send_ndjson(_port, map) do
      Agent.update(__MODULE__, &[map | &1])
      :ok
    end

    def cancel(_port), do: :ok
  end

  setup do
    Application.put_env(:eye_in_the_sky, :pi_cli_module, StubCLI)
    case StubCLI.start_link() do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> Agent.update(StubCLI, fn _ -> [] end)
    end
    on_exit(fn -> Application.delete_env(:eye_in_the_sky, :pi_cli_module) end)
    :ok
  end

  # Control runs its receive loop in a Task; the StubCLI can't know the ref the
  # Task sees. So these tests drive via a responder function hook instead:
  # Control accepts a :responder opt (test-only) called with each sent request,
  # returning the raw line(s) to deliver. Simpler: test the pure response
  # matcher and the request sequencing separately.

  test "discover_models sends initialize then discover_models with ctl ids" do
    # responder echoes success for every request id
    responder = fn %{id: id, type: type} ->
      data =
        case type do
          "initialize" -> ~s({"protocolVersion":1})
          "discover_models" -> ~s({"models":[{"id":"ollama-lan/qwen3.6:27b","provider":"ollama-lan"}]})
        end

      ~s({"id":"#{id}","type":"response","command":"#{type}","success":true,"data":#{data}})
    end

    assert {:ok, [%{"id" => "ollama-lan/qwen3.6:27b"}]} =
             Control.discover_models(responder: responder)

    types = StubCLI.sends() |> Enum.map(& &1.type)
    assert types == ["initialize", "discover_models"]
  end

  test "failed response surfaces the harness error" do
    responder = fn %{id: id, type: type} ->
      case type do
        "initialize" ->
          ~s({"id":"#{id}","type":"response","command":"initialize","success":true,"data":{"protocolVersion":1}})

        "set_api_key" ->
          ~s({"id":"#{id}","type":"response","command":"set_api_key","success":false,"error":"unknown provider"})
      end
    end

    assert {:error, {:pi_control, "unknown provider"}} =
             Control.set_api_key("nope", "sk-x", responder: responder)
  end

  test "set_api_key sends providerId and key, returns :ok on success" do
    responder = fn %{id: id, type: type} ->
      ~s({"id":"#{id}","type":"response","command":"#{type}","success":true,"data":true})
    end

    assert :ok = Control.set_api_key("openrouter", "sk-or-123", responder: responder)
    assert %{type: "set_api_key", providerId: "openrouter", key: "sk-or-123"} =
             Enum.find(StubCLI.sends(), &(&1.type == "set_api_key"))
  end

  test "timeout returns error" do
    responder = fn %{type: "initialize", id: id} ->
      ~s({"id":"#{id}","type":"response","command":"initialize","success":true,"data":{"protocolVersion":1}})
    end

    # responder returns nil for discover_models -> nothing delivered -> timeout
    responder = fn
      %{type: "initialize"} = req -> responder.(req)
      _ -> nil
    end

    assert {:error, :pi_control_timeout} =
             Control.discover_models(responder: responder, timeout: 200)
  end
end
```

- [ ] **Step 2: Run to verify failure** — `mix test test/eye_in_the_sky/pi/control_test.exs` → FAIL (module undefined).

- [ ] **Step 3: Implement**

```elixir
defmodule EyeInTheSky.Pi.Control do
  @moduledoc """
  One-shot harness IPC for non-chat Pi verbs (spec §4 Pi.Control).

  Each call spawns the harness, performs initialize -> <verb> -> response,
  then tears the process down. Runs inside a Task so harness output never
  lands in the caller's mailbox (LiveViews call this directly).

  OAuth verbs are Phase 3. Credentials go to ~/.pi/agent/auth.json via the
  harness — never through EITS Settings, never logged.
  """

  alias EyeInTheSky.Claude.Utils

  require Logger

  @default_timeout 30_000

  def discover_models(opts \\ []),
    do: one_shot("discover_models", %{}, & &1["models"], opts)

  def list_providers(opts \\ []),
    do: one_shot("list_providers", %{}, & &1, opts)

  def auth_status(opts \\ []),
    do: one_shot("auth_status", %{}, & &1, opts)

  def set_api_key(provider_id, key, opts \\ [])
      when is_binary(provider_id) and is_binary(key) do
    case one_shot("set_api_key", %{providerId: provider_id, key: key}, fn _ -> :ok end, opts) do
      {:ok, :ok} -> :ok
      other -> other
    end
  end

  def clear_api_key(provider_id, opts \\ []) when is_binary(provider_id) do
    case one_shot("clear_api_key", %{providerId: provider_id}, fn _ -> :ok end, opts) do
      {:ok, :ok} -> :ok
      other -> other
    end
  end

  # -- internals ---------------------------------------------------------------

  defp one_shot(command, payload, extract, opts) do
    timeout = opts[:timeout] || @default_timeout

    task =
      Task.async(fn ->
        run_one_shot(command, payload, extract, opts, timeout)
      end)

    # Outer await is generous: the inner receive enforces the real timeout.
    Task.await(task, timeout + 5_000)
  catch
    :exit, reason -> {:error, {:pi_control_crashed, reason}}
  end

  defp run_one_shot(command, payload, extract, opts, timeout) do
    cli = Utils.pi_cli_module()
    responder = opts[:responder]

    with {:ok, port, ref} <- cli.spawn_harness(caller: self(), project_path: File.cwd!()) do
      try do
        with {:ok, _} <- request(cli, port, ref, %{id: "ctl-1", type: "initialize", protocolVersion: 1}, responder, timeout),
             req = Map.merge(%{id: "ctl-2", type: command}, payload),
             {:ok, data} <- request(cli, port, ref, req, responder, timeout) do
          {:ok, extract.(data)}
        end
      after
        # Harness exits on dispose; cancel is the belt-and-braces fallback.
        cli.send_ndjson(port, %{id: "ctl-3", type: "dispose"})
        cli.cancel(port)
      end
    end
  end

  defp request(cli, port, ref, req, responder, timeout) do
    :ok = cli.send_ndjson(port, req)

    # Test seam: a responder synthesizes the harness's reply line.
    if responder do
      case responder.(req) do
        nil -> :ok
        line -> send(self(), {:claude_output, ref, line})
      end
    end

    await_response(ref, req.id, timeout)
  end

  defp await_response(ref, id, timeout) do
    receive do
      {:claude_output, ^ref, line} ->
        case Jason.decode(line) do
          {:ok, %{"type" => "response", "id" => ^id, "success" => true} = r} ->
            {:ok, r["data"]}

          {:ok, %{"type" => "response", "id" => ^id, "success" => false} = r} ->
            {:error, {:pi_control, r["error"]}}

          _other ->
            # unsolicited events / other ids — keep waiting
            await_response(ref, id, timeout)
        end

      {:claude_exit, ^ref, code} ->
        {:error, {:harness_exit, code}}
    after
      timeout -> {:error, :pi_control_timeout}
    end
  end
end
```

Note the untestable-by-stub subtlety the tests dodge via `:responder`: in production the CLI's port handler delivers `{:claude_output, ref, line}` to the Task process because `caller: self()` inside the Task. The `ref` in `await_response` matches on the ref returned by `spawn_harness` — in the stub that ref differs from the fed one, which is why the responder sends with the same `ref` closure variable. Implementer: make sure `request/6` and `await_response/3` use the ref from `spawn_harness`'s return, as shown.

- [ ] **Step 4: Run tests** — `mix test test/eye_in_the_sky/pi/control_test.exs` → all PASS.

- [ ] **Step 5: One live smoke (manual, harness must be built):**

```bash
mix run -e 'IO.inspect(EyeInTheSky.Pi.Control.discover_models())' | tail -3
```

Expected: `{:ok, [...]}` including `ollama-lan/qwen3.6:27b`.

- [ ] **Step 6: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/pi/control.ex test/eye_in_the_sky/pi/control_test.exs
git commit -m "feat(pi): Pi.Control one-shot harness IPC (discover/list/auth/set_key/clear_key)"
```

---

### Task 2: ModelDiscoveryCache

**Files:**
- Create: `lib/eye_in_the_sky/pi/model_discovery_cache.ex`
- Modify: `lib/eye_in_the_sky/application.ex` (add child after `EyeInTheSky.IAM.PolicyCache`)
- Test: `test/eye_in_the_sky/pi/model_discovery_cache_test.exs`

**Interfaces:**
- Consumes: `Pi.Control.discover_models/0` (Task 1).
- Produces (Tasks 5/6 rely on):
  - `get_cached/0 :: {:ok, [model_map], :fresh | :stale} | :empty` — **never blocks, never calls the harness.** Reads ETS only.
  - `refresh/0 :: {:ok, [model_map]} | {:error, term}` — synchronous refresh through the GenServer (30 s call timeout); on success stores with `expires_at = now + 60_000`.
  - `refresh_async/0 :: :ok` — casts a refresh; callers that subscribed via `subscribe/0` get `{:pi_models_refreshed, {:ok, models} | {:error, term}}`.
  - `subscribe/0` — PubSub via `EyeInTheSky.Events` (add `Events.subscribe_pi_models/0` + `Events.pi_models_refreshed/1` named functions per lib/CLAUDE.md rule — never call Phoenix.PubSub directly).
  - `invalidate/0 :: :ok` — clears ETS (Task 6 calls after set/clear key).

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EyeInTheSky.Pi.ModelDiscoveryCacheTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi.ModelDiscoveryCache, as: Cache

  # Control seam: cache reads its control module from app env.
  defmodule FakeControl do
    def discover_models do
      case Process.get(:fake_result) || Application.get_env(:eye_in_the_sky, :fake_discover) do
        nil -> {:ok, [%{"id" => "ollama/mistral"}]}
        result -> result
      end
    end
  end

  setup do
    Application.put_env(:eye_in_the_sky, :pi_control_module, FakeControl)
    on_exit(fn ->
      Application.delete_env(:eye_in_the_sky, :pi_control_module)
      Application.delete_env(:eye_in_the_sky, :fake_discover)
      Cache.invalidate()
    end)
    :ok
  end

  test "get_cached is :empty before any refresh" do
    Cache.invalidate()
    assert :empty = Cache.get_cached()
  end

  test "refresh stores models; get_cached returns :fresh" do
    Application.put_env(:eye_in_the_sky, :fake_discover, {:ok, [%{"id" => "a/b"}]})
    assert {:ok, [%{"id" => "a/b"}]} = Cache.refresh()
    assert {:ok, [%{"id" => "a/b"}], :fresh} = Cache.get_cached()
  end

  test "entries older than TTL read as :stale but are still returned" do
    Application.put_env(:eye_in_the_sky, :fake_discover, {:ok, [%{"id" => "a/b"}]})
    {:ok, _} = Cache.refresh()
    Cache.__force_expire_for_test__()
    assert {:ok, [%{"id" => "a/b"}], :stale} = Cache.get_cached()
  end

  test "refresh failure keeps the previous cached list" do
    Application.put_env(:eye_in_the_sky, :fake_discover, {:ok, [%{"id" => "a/b"}]})
    {:ok, _} = Cache.refresh()
    Application.put_env(:eye_in_the_sky, :fake_discover, {:error, :pi_control_timeout})
    assert {:error, :pi_control_timeout} = Cache.refresh()
    assert {:ok, [%{"id" => "a/b"}], _} = Cache.get_cached()
  end

  test "invalidate clears" do
    Application.put_env(:eye_in_the_sky, :fake_discover, {:ok, [%{"id" => "a/b"}]})
    {:ok, _} = Cache.refresh()
    Cache.invalidate()
    assert :empty = Cache.get_cached()
  end
end
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** (PolicyCache pattern: named GenServer owns a public ETS table; reads never call the server)

```elixir
defmodule EyeInTheSky.Pi.ModelDiscoveryCache do
  @moduledoc """
  ETS-backed cache of Pi model discovery (spec Phase 2).

  TTL #{60_000} ms — past-TTL entries read as :stale but remain served until a
  refresh succeeds (discovery failure must never blank the picker). Invalidate
  on set_api_key / clear_api_key. get_cached/0 NEVER touches the harness.
  """

  use GenServer

  require Logger

  @table :pi_model_discovery
  @ttl_ms 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec get_cached() :: {:ok, [map()], :fresh | :stale} | :empty
  def get_cached do
    case :ets.lookup(@table, :models) do
      [{:models, list, expires_at}] ->
        freshness = if System.monotonic_time(:millisecond) < expires_at, do: :fresh, else: :stale
        {:ok, list, freshness}

      [] ->
        :empty
    end
  end

  @spec refresh() :: {:ok, [map()]} | {:error, term()}
  def refresh, do: GenServer.call(__MODULE__, :refresh, 35_000)

  @spec refresh_async() :: :ok
  def refresh_async, do: GenServer.cast(__MODULE__, :refresh)

  @spec invalidate() :: :ok
  def invalidate do
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc false
  def __force_expire_for_test__ do
    case :ets.lookup(@table, :models) do
      [{:models, list, _}] -> :ets.insert(@table, {:models, list, 0})
      [] -> :ok
    end

    :ok
  end

  # -- GenServer ---------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call(:refresh, _from, state), do: {:reply, do_refresh(), state}

  @impl true
  def handle_cast(:refresh, state) do
    result = do_refresh()
    EyeInTheSky.Events.pi_models_refreshed(result)
    {:noreply, state}
  end

  defp do_refresh do
    case control_module().discover_models() do
      {:ok, models} when is_list(models) ->
        expires_at = System.monotonic_time(:millisecond) + @ttl_ms
        :ets.insert(@table, {:models, models, expires_at})
        {:ok, models}

      {:error, reason} ->
        Logger.warning("[Pi.ModelDiscoveryCache] refresh failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp control_module,
    do: Application.get_env(:eye_in_the_sky, :pi_control_module, EyeInTheSky.Pi.Control)
end
```

Add to `EyeInTheSky.Events` (follow the module's existing style; topic `"pi:models"`):

```elixir
  def subscribe_pi_models, do: Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "pi:models")
  def pi_models_refreshed(result),
    do: Phoenix.PubSub.broadcast(EyeInTheSky.PubSub, "pi:models", {:pi_models_refreshed, result})
```

Add child in `application.ex` children list (after `PolicyCache`): `EyeInTheSky.Pi.ModelDiscoveryCache,`

- [ ] **Step 4: Run tests** — cache tests + `mix test test/eye_in_the_sky/pi` all PASS.

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/pi/model_discovery_cache.ex lib/eye_in_the_sky/application.ex lib/eye_in_the_sky/events.ex test/eye_in_the_sky/pi/model_discovery_cache_test.exs
git commit -m "feat(pi): model discovery cache (ETS, 60s TTL, stale-serving, pubsub refresh)"
```

---

### Task 3: Pi error-category classification (spec §7)

**Files:**
- Modify: `lib/eye_in_the_sky/claude/agent_worker/error_classifier.ex` (category type at :22-29, add clauses near `:user_canceled` at :51-54, `status_reason/1` at :107)
- Modify: `lib/eye_in_the_sky_web/helpers/status_helpers.ex` (`failed_tier/1` :50-52, `status_label/1` :128, `status_to_badge/1` :135)
- Test: extend `test/eye_in_the_sky/claude/agent_worker/error_classifier_test.exs`

**Interfaces:**
- Consumes: Pi errors arrive as `{:pi_turn_error, msg :: String.t()}` (from Pi.SDK) — msg is the harness-rendered provider error markdown, e.g. `"**Error · HTTP 400**\n\nYou're out of extra usage...\n\n_invalid_request_error_"`.
- Produces: `classify({:pi_turn_error, msg})` returns `:billing_error | :authentication_error | :rate_limit_error | :model_not_found | :transient`; new `:model_not_found` category is systemic (no retry) with status_reason `"model_not_found"`, badge `failed_model`, label `"Model not found"`.

- [ ] **Step 1: Write the failing tests** (extend the existing test file, matching its style):

```elixir
  describe "pi_turn_error content mapping" do
    test "usage/quota/billing -> :billing_error (systemic)" do
      for msg <- [
            "**Error · HTTP 400**\n\nYou're out of extra usage. Add more at claude.ai/settings/usage.\n\n_invalid_request_error_",
            "insufficient quota for this request",
            "credit balance is too low"
          ] do
        assert ErrorClassifier.classify({:pi_turn_error, msg}) == :billing_error
        assert ErrorClassifier.systemic?({:pi_turn_error, msg})
      end
    end

    test "auth -> :authentication_error" do
      for msg <- ["HTTP 401 authentication_error", "invalid api key provided", "HTTP 403 forbidden"] do
        assert ErrorClassifier.classify({:pi_turn_error, msg}) == :authentication_error
      end
    end

    test "rate limit -> :rate_limit_error (retryable)" do
      for msg <- ["HTTP 429 rate_limit_error", "Rate limit exceeded", "overloaded_error"] do
        assert ErrorClassifier.classify({:pi_turn_error, msg}) == :rate_limit_error
        refute ErrorClassifier.systemic?({:pi_turn_error, msg})
      end
    end

    test "model 404 -> :model_not_found (systemic, no retry)" do
      msg = "**Error · HTTP 404**\n\nmodel: claude-3-5-haiku-20241022\n\n_not_found_error_"
      assert ErrorClassifier.classify({:pi_turn_error, msg}) == :model_not_found
      assert ErrorClassifier.systemic?({:pi_turn_error, msg})
      assert ErrorClassifier.status_reason({:pi_turn_error, msg}) == "model_not_found"
    end

    test "unrecognized pi error -> :transient" do
      assert ErrorClassifier.classify({:pi_turn_error, "connection reset by peer"}) == :transient
    end
  end
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement.** In `error_classifier.ex`: extend the `@type category` union with `:model_not_found`; add clauses **above** the `{:claude_result_error, ...}` block:

```elixir
  # Pi harness renders provider errors as markdown text — classify by content.
  # Order matters: billing before auth (a 400 usage error must not read as generic).
  def classify({:pi_turn_error, msg}) when is_binary(msg) do
    cond do
      msg =~ ~r/out of .*usage|quota|credit|billing/iu -> :billing_error
      msg =~ ~r/HTTP 429|rate.?limit|overloaded/iu -> :rate_limit_error
      msg =~ ~r/HTTP 40[13]|authentication|invalid[ _]?(api[ _-]?key|x-api-key|token)/iu -> :authentication_error
      msg =~ ~r/HTTP 404|not_found_error|unknown model/iu -> :model_not_found
      true -> :transient
    end
  end

  def classify({:pi_turn_error, _}), do: :transient
```

`status_reason/1` needs no change if it already stringifies non-transient categories generically — verify; if it pattern-matches categories explicitly, add `:model_not_found`. In `status_helpers.ex` add: `failed_tier("model_not_found") -> "failed_model"` (match existing arity/shape at :50-52), `status_label("failed_model") -> "Model not found"`, `status_to_badge("failed_model") -> "badge-error"`.

- [ ] **Step 4: Run** — classifier tests + `mix test test/eye_in_the_sky/claude/agent_worker` all PASS (no existing behavior change: new clauses only match `{:pi_turn_error, _}` tuples, which previously fell to the catch-all).

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/claude/agent_worker/error_classifier.ex lib/eye_in_the_sky_web/helpers/status_helpers.ex test/eye_in_the_sky/claude/agent_worker/error_classifier_test.exs
git commit -m "feat(pi): classify pi_turn_error content into billing/auth/rate-limit/model_not_found categories"
```

---

### Task 4: Inline provider-error rendering in chat

**Files:**
- Modify: `lib/eye_in_the_sky/agent_worker_events.ex` (`on_session_failed/2` at :102-111, `failure_message/1` at :152)
- Test: `test/eye_in_the_sky/agent_worker_events_error_message_test.exs`

**Design (from exploration):** `{:agent_error, ...}` broadcasts are dropped by every LiveView, and `messages.failure_reason` is never rendered. But `on_spawn_error/2` (:114-122) already injects a visible transcript message via `Messages.record_incoming_reply(session_id, "system", "[spawn error] ...")` — and system messages DO render in chat and broadcast live. Reuse exactly that: on systemic failure, persist a `"system"` message carrying the human-readable error. No LiveView changes needed; reconnects see it for free because it's a real message. This is intentionally provider-wide (Claude/Codex billing errors get the same visibility).

**Interfaces:**
- Consumes: `ErrorClassifier.status_reason/1`, `Messages.record_incoming_reply/3` (same call shape as `on_spawn_error/2`).
- Produces: on `on_session_failed(session_id, reason)`, a persisted system message `"[provider error] <sanitized text>"`.

- [ ] **Step 1: Write the failing test** (DataCase; follow whatever test template `agent_worker_events` / `messages` tests already use — check `test/eye_in_the_sky/` for a `Messages` test to copy setup from):

```elixir
defmodule EyeInTheSky.AgentWorkerEventsErrorMessageTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{AgentWorkerEvents, Messages}

  # Use existing fixtures/factories for a session — copy the setup pattern from
  # the nearest messages/agent_worker_events test file.

  test "on_session_failed persists a system message with the sanitized error", %{} do
    session = insert_session_fixture()  # implementer: reuse the repo's existing session fixture helper

    AgentWorkerEvents.on_session_failed(
      session.id,
      {:pi_turn_error, "**Error · HTTP 400**\n\nYou're out of extra usage.\n\n_invalid_request_error_"}
    )

    messages = Messages.list_for_session(session.id)
    assert Enum.any?(messages, fn m ->
             m.sender_role == "system" and m.body =~ "provider error" and m.body =~ "out of extra usage"
           end)
  end

  test "the system error message never contains key-like material" do
    session = insert_session_fixture()
    AgentWorkerEvents.on_session_failed(session.id, {:pi_turn_error, "bad key sk-or-abcdef1234567890"})
    [msg] = Messages.list_for_session(session.id) |> Enum.filter(&(&1.sender_role == "system"))
    refute msg.body =~ "sk-or-abcdef1234567890"
  end
end
```

(Adapt fixture/list function names to what actually exists — `Messages.list_for_session/1` name must be verified; if the context exposes a different reader, use it in both test and assertion.)

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement.** In `agent_worker_events.ex`, inside `on_session_failed/2` (after the status update, before/alongside the existing `Events.stream_error` call):

```elixir
    error_text = provider_error_text(reason)
    Messages.record_incoming_reply(session_id, "system", "[provider error] " <> error_text)
    Events.stream_error(session_id, provider_conversation_id, error_text)
```

with:

```elixir
  # Human-readable, key-redacted error text for transcript + stream broadcast.
  defp provider_error_text({:pi_turn_error, msg}) when is_binary(msg), do: redact(msg)
  defp provider_error_text({:claude_result_error, %{result: result}}) when is_binary(result), do: redact(result)
  defp provider_error_text(reason), do: reason |> inspect() |> redact() |> String.slice(0, 500)

  @key_pattern ~r/\b(sk|key|token)[-_][A-Za-z0-9_\-]{8,}\b/i
  defp redact(text), do: Regex.replace(@key_pattern, text, "[redacted]")
```

Check the current `on_session_failed/2` signature first — if it takes `(session_id, pcid)` and the reason isn't available there, thread the reason from `ErrorRecovery.handle_systemic_error/2` (which has it) into the call; that's a 2-line change in `error_recovery.ex:118-126` and MUST keep the existing arity available or update its only callers (grep `on_session_failed` — exploration says it's called from the systemic path only).

- [ ] **Step 4: Run** — new test + `mix test test/eye_in_the_sky/claude/agent_worker test/eye_in_the_sky/pi` PASS.

- [ ] **Step 5: Manual verify** — with the usage-capped anthropic credential (or a bogus model id), send a message to a Pi session; the chat should now show a `[provider error] ...` system bubble instead of silence.

- [ ] **Step 6: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/agent_worker_events.ex lib/eye_in_the_sky/claude/agent_worker/error_recovery.ex test/eye_in_the_sky/agent_worker_events_error_message_test.exs
git commit -m "feat: persist provider errors as system messages in chat (systemic failures were invisible)"
```

---

### Task 5: Spawn drawer Pi model picker

**Files:**
- Modify: `lib/eye_in_the_sky_web/helpers/model_helpers.ex` (add `pi_models/0`, extend `models_for_provider/1` at :78, `default_model_for/1` at :106)
- Modify: `lib/eye_in_the_sky_web/components/new_agent_drawer.ex` (agent-type select :41-44, model select :49-61)
- Test: `test/eye_in_the_sky_web/helpers/model_helpers_pi_test.exs`

**Interfaces:**
- Consumes: `ModelDiscoveryCache.get_cached/0` (Task 2 shape).
- Produces: `ModelHelpers.pi_models/0 :: {[slug :: String.t()], :fresh | :stale | :empty}`.

- [ ] **Step 1: Failing test**

```elixir
defmodule EyeInTheSkyWeb.ModelHelpersPiTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Pi.ModelDiscoveryCache, as: Cache
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  setup do
    Application.put_env(:eye_in_the_sky, :pi_control_module, __MODULE__.FakeControl)
    on_exit(fn ->
      Application.delete_env(:eye_in_the_sky, :pi_control_module)
      Cache.invalidate()
    end)
  end

  defmodule FakeControl do
    def discover_models, do: {:ok, [%{"id" => "ollama-lan/qwen3.6:27b"}, %{"id" => "google/gemini-2.5-pro"}]}
  end

  test "pi_models returns cached slugs with freshness" do
    {:ok, _} = Cache.refresh()
    assert {["ollama-lan/qwen3.6:27b", "google/gemini-2.5-pro"], :fresh} = ModelHelpers.pi_models()
  end

  test "pi_models is empty-safe" do
    Cache.invalidate()
    assert {[], :empty} = ModelHelpers.pi_models()
  end

  test "models_for_provider pi delegates to discovery" do
    {:ok, _} = Cache.refresh()
    assert "ollama-lan/qwen3.6:27b" in ModelHelpers.models_for_provider("pi")
  end
end
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement.** `model_helpers.ex`:

```elixir
  @doc "Discovered Pi model slugs from the cache. Never calls the harness."
  @spec pi_models() :: {[String.t()], :fresh | :stale | :empty}
  def pi_models do
    case EyeInTheSky.Pi.ModelDiscoveryCache.get_cached() do
      {:ok, models, freshness} -> {Enum.map(models, & &1["id"]), freshness}
      :empty -> {[], :empty}
    end
  end
```

Extend `models_for_provider/1`: `def models_for_provider("pi"), do: pi_models() |> elem(0)` (clause above the default). `default_model_for("pi")` returns `nil` (matches `ModelConfig.default_model("pi")`).

`new_agent_drawer.ex`:
1. Agent-type select (:41-44): add `<option value="pi">Pi (multi-provider)</option>`.
2. Model select (:49-61): third optgroup —

```heex
<% {pi_slugs, pi_freshness} = pi_models() %>
<optgroup label={pi_optgroup_label(pi_freshness)}>
  <option :for={slug <- pi_slugs} value={slug}>{slug}</option>
  <option :if={pi_slugs == []} disabled>No Pi providers configured — Settings → Providers</option>
</optgroup>
```

with a private helper in the component: `defp pi_optgroup_label(:stale), do: "Pi (discovered — stale)"` / `defp pi_optgroup_label(_), do: "Pi (discovered)"`. Import `pi_models: 0` alongside the existing model imports (:14-15).
3. On component mount/update, call `ModelDiscoveryCache.refresh_async()` once so opening the drawer warms the cache for next render — do NOT block render on it.

- [ ] **Step 4: Run tests + visual check** — tests PASS; open the New Agent drawer at localhost:5001, confirm the Pi optgroup appears, selecting Pi + a discovered model spawns (reuse the working ollama-lan model).

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky_web/helpers/model_helpers.ex lib/eye_in_the_sky_web/components/new_agent_drawer.ex test/eye_in_the_sky_web/helpers/model_helpers_pi_test.exs
git commit -m "feat(pi): spawn drawer Pi optgroup fed by discovery cache"
```

---

### Task 6: Settings → Providers tab

**Files:**
- Create: `lib/eye_in_the_sky_web/live/overview_live/settings/providers_tab.ex`
- Modify: `lib/eye_in_the_sky_web/live/overview_live/settings.ex` (`@valid_tabs` :34, tab bar :317-331, `render_tab/1` :338-347, alias block :14-22, new handle_events)
- Test: `test/eye_in_the_sky_web/live/settings_providers_tab_test.exs`

**Interfaces:**
- Consumes: `Pi.Control.list_providers/0`, `set_api_key/2`, `clear_api_key/1` (Task 1); `ModelDiscoveryCache.{invalidate/0, refresh_async/0, get_cached/0}` (Task 2).
- Produces: `/settings?tab=providers` page.

**Behavior:**
- On entering the tab (`handle_params` when tab == :providers, or first render): `assign_async`-style load of `Pi.Control.list_providers()` into `@pi_providers` (`{:loading} | {:ok, providers} | {:error, reason}`). **Do not capture socket in the async closure** (lib/.claude rule).
- Each provider row: label, configured badge (`authSource` present → `badge-success "configured"`, else `badge-ghost "not set"`), a password-type input + Save (event `"pi_set_key"`, params `provider_id`, `key`), Clear button (event `"pi_clear_key"`) only when configured.
- `pi_set_key`: `Pi.Control.set_api_key(pid, key)` → on `:ok`: `ModelDiscoveryCache.invalidate(); ModelDiscoveryCache.refresh_async()`, reload providers, flash "Key saved to ~/.pi/agent/auth.json". On error: flash the error. **Never put the key into logs, flashes, or assigns beyond the form param.**
- "Refresh models" button (`"pi_refresh_models"`) → `refresh_async()`; subscribe to `Events.subscribe_pi_models()` in mount (connected-only guard!) and update a `@pi_model_count`/freshness line on `{:pi_models_refreshed, _}`.
- Copy block (spec §5, verbatim requirement): *"EITS Pi uses ~/.pi/agent/auth.json only. Environment credentials (including ANTHROPIC_API_KEY) are intentionally not passed into the harness."*
- Card/DaisyUI structure: copy `auth_tab.ex` scaffolding (`card bg-base-100 border border-base-300 shadow-sm` → `card-body p-0 divide-y divide-base-300` → `px-5 py-4` rows). OAuth-kind providers render a disabled "Sign in (Phase 3)" button — no oauth verbs.

- [ ] **Step 1: Failing LiveView test** (use the repo's existing settings LiveView test as the template for auth/setup; stub `pi_control_module` with a fake returning two providers, one configured):

```elixir
defmodule EyeInTheSkyWeb.SettingsProvidersTabTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defmodule FakeControl do
    def list_providers,
      do: {:ok, %{"providers" => [
        %{"id" => "openrouter", "label" => "OpenRouter", "kind" => "api", "configured" => false},
        %{"id" => "anthropic", "label" => "Anthropic", "kind" => "oauth", "configured" => true}
      ]}}

    def set_api_key("openrouter", _key), do: :ok
    def clear_api_key("anthropic"), do: :ok
    def discover_models, do: {:ok, []}
  end

  setup do
    Application.put_env(:eye_in_the_sky, :pi_control_module, FakeControl)
    on_exit(fn -> Application.delete_env(:eye_in_the_sky, :pi_control_module) end)
    :ok
  end

  test "providers tab lists providers with configured badges", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings?tab=providers")
    html = render_async(view)
    assert html =~ "OpenRouter"
    assert html =~ "auth.json"
  end

  test "saving a key calls set_api_key and flashes success", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/settings?tab=providers")
    render_async(view)
    view
    |> element(~s(form[phx-submit="pi_set_key"][phx-value-provider_id="openrouter"]))
    |> render_submit(%{"key" => "sk-or-test"})
    assert render(view) =~ "Key saved"
  end
end
```

(Adapt selectors to the real markup you write; the assertions that matter: providers listed, save path calls Control and confirms, key value never echoed back into the HTML.)

**Important:** `Pi.Control` must read its module seam for LiveView code too — Task 6 adds `defp control(), do: Application.get_env(:eye_in_the_sky, :pi_control_module, EyeInTheSky.Pi.Control)` in the settings LiveView (mirroring the cache's seam) and routes all calls through it.

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** per the behavior block. Registration edits in `settings.ex`: add `"providers"` to `@valid_tabs`, `{"Providers", "providers"}` to the tab list, `defp render_tab(%{active_tab: :providers} = assigns), do: ProvidersTab.render(assigns)`, alias `ProvidersTab`.

- [ ] **Step 4: Run** — LiveView test + `mix test test/eye_in_the_sky_web/live` (pre-existing failures per baseline notes are acceptable; no NEW failures).

- [ ] **Step 5: Manual verify** — `/settings?tab=providers`: providers listed, set a throwaway OpenRouter key → configured badge flips, model refresh works, `command cat ~/.pi/agent/auth.json` shows the entry (then clear it).

- [ ] **Step 6: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky_web/live/overview_live/settings.ex lib/eye_in_the_sky_web/live/overview_live/settings/providers_tab.ex test/eye_in_the_sky_web/live/settings_providers_tab_test.exs
git commit -m "feat(pi): /settings Providers tab — API key set/clear via auth.json, model refresh"
```

---

## Execution Waves (team)

- **Wave 1 (parallel, disjoint files):** Agent A: Tasks 1+2 (control + cache). Agent B: Task 3 (classifier). Agent C: Task 4 (error message).
- **Wave 2 (after wave 1 merges):** Agent D: Tasks 5+6 (picker + settings tab — both consume Control/Cache).
- Codex review of the integrated branch, then merge to `features`.

## Self-Review Notes

- Spec Phase-2 coverage: Control verbs ✓ (Task 1, oauth excluded per Phase 3), cache TTL 60 s + invalidation on key change + manual refresh ✓ (Tasks 2/6), spawn picker from discovery ✓ (Task 5), settings set/clear key ✓ (Task 6), settings copy verbatim ✓ (Task 6), discovery-failure UX (stale serve + hint + manual entry stays possible via free-form model validation) ✓ (Tasks 2/5), atomic-auth-write verification before enabling set/clear (spec §4): **Task 6 Step 5 includes inspecting auth.json after a write; add to that step: confirm `provider-auth.ts` writes via lock/atomic replace (read the vendored source; if it lacks atomic replace, add temp-file+rename in a harness commit).** Follow-ups: classifier categories ✓ (Task 3), inline errors ✓ (Task 4).
- Type consistency: `get_cached/0` shape used identically in Tasks 2/5/6; `pi_control_module` seam name shared by Tasks 2/6; `{:pi_turn_error, msg}` shape matches Phase 1's SDK output.
- Known judgment call: error transcript message uses `record_incoming_reply(session_id, "system", ...)` — the proven rendering path — instead of new LiveView handlers for the orphaned `{:agent_error, ...}` broadcast.
