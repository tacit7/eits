defmodule EyeInTheSky.Codex.AppServer do
  @moduledoc """
  Long-lived owner for one Codex app-server process.

  Ownership contract:
  - one GenServer is registered per EITS AgentWorker/session key;
  - the GenServer owns the OS Port, JSON-RPC IDs, pending requests, thread id,
    active turn id, turn buffers, cancellation, exit cleanup, and server-request
    replies;
  - AgentWorker remains the queue and persistence owner and sees only the
    existing Claude-compatible SDK tuples.
  """

  use GenServer, restart: :transient

  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Codex.AppServer.{Protocol, TurnBuffer}

  require Logger

  @registry EyeInTheSky.Codex.AppServerRegistry
  @supervisor EyeInTheSky.Codex.AppServerSupervisor
  @request_timeout_ms 30_000
  @interrupt_timeout_ms 5_000
  @cancel_terminal_timeout_ms 10_000
  @client_version "eits"
  @blocked_env_vars ~w[
    SECRET_KEY_BASE
    DATABASE_URL
    ANTHROPIC_API_KEY
    CLAUDECODE
    CLAUDE_CODE_ENTRYPOINT
    ENTRYPOINT
    BINDIR
    ROOTDIR
    EMU
  ]
  @blocked_env_prefixes ["RELEASE_"]

  defstruct [
    :owner_key,
    :project_path,
    :port,
    :transport_pid,
    :thread_id,
    :resume_thread_id,
    :active_turn,
    :next_id,
    :stdout_buffer,
    pending: %{},
    initialized?: false
  ]

  @doc """
  Looks up or starts the app-server registered for `owner_key`.
  """
  def lookup_or_start(owner_key, opts) do
    case Registry.lookup(@registry, owner_key) do
      [{pid, _}] when is_pid(pid) ->
        emit_telemetry(:lookup, %{reused: true}, %{owner_key: owner_key})
        {:ok, pid}

      [] ->
        child_opts =
          opts
          |> Keyword.put(:owner_key, owner_key)

        case DynamicSupervisor.start_child(@supervisor, {__MODULE__, child_opts}) do
          {:ok, pid} ->
            emit_telemetry(:started, %{}, %{owner_key: owner_key})
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            emit_telemetry(:lookup, %{reused: true}, %{owner_key: owner_key})
            {:ok, pid}

          {:error, reason} ->
            emit_telemetry(:start_failed, %{}, %{owner_key: owner_key, reason: reason})
            {:error, reason}
        end
    end
  end

  def start_link(opts) do
    owner_key = Keyword.fetch!(opts, :owner_key)
    name = {:via, Registry, {@registry, owner_key}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def start_turn(pid, sdk_ref, caller_pid, prompt, opts) do
    timeout = Keyword.get(opts, :app_server_call_timeout_ms, 60_000)
    GenServer.call(pid, {:start_turn, sdk_ref, caller_pid, prompt, opts}, timeout)
  end

  def list_hooks(pid, cwds, opts \\ []) when is_list(cwds) do
    timeout = Keyword.get(opts, :app_server_call_timeout_ms, 60_000)
    GenServer.call(pid, {:list_hooks, cwds}, timeout)
  end

  def interrupt(pid) do
    GenServer.call(pid, :interrupt, @interrupt_timeout_ms)
  catch
    :exit, _ -> {:error, :not_found}
  end

  def stop_owner(owner_key) do
    if named_process?(@registry) and named_process?(@supervisor) do
      case Registry.lookup(@registry, owner_key) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(@supervisor, pid)
        [] -> :ok
      end
    else
      :ok
    end
  rescue
    ArgumentError -> :ok
  catch
    :exit, _ -> :ok
  end

  defp named_process?(name), do: is_pid(Process.whereis(name))

  @impl true
  def init(opts) do
    owner_key = Keyword.fetch!(opts, :owner_key)
    project_path = opts |> Keyword.get(:project_path, File.cwd!()) |> Path.expand()

    if File.dir?(project_path) do
      case open_transport(opts, project_path) do
        {:ok, %{port: port, transport_pid: transport_pid}} ->
          {:ok,
           %__MODULE__{
             owner_key: owner_key,
             project_path: project_path,
             port: port,
             transport_pid: transport_pid,
             next_id: 1,
             stdout_buffer: ""
           }}

        {:error, reason} ->
          {:stop, reason}
      end
    else
      {:stop, {:invalid_project_path, project_path}}
    end
  end

  @impl true
  def handle_call(
        {:start_turn, sdk_ref, caller_pid, prompt, opts},
        from,
        %__MODULE__{active_turn: nil} = state
      ) do
    turn = %{
      sdk_ref: sdk_ref,
      caller_pid: caller_pid,
      from: from,
      prompt: prompt,
      opts: opts,
      turn_id: nil,
      buffer: TurnBuffer.new(),
      cancel_timer: nil,
      terminal?: false
    }

    state = %{state | active_turn: turn, resume_thread_id: opts[:resume_thread_id]}

    if state.initialized? do
      {:noreply, ensure_thread(state)}
    else
      {:noreply,
       send_request(
         state,
         "initialize",
         Protocol.initialize_request(next_id(state), @client_version),
         :initialize
       )}
    end
  end

  @impl true
  def handle_call({:start_turn, _ref, _caller, _prompt, _opts}, _from, state) do
    {:reply, {:error, :turn_already_active}, state}
  end

  @impl true
  def handle_call({:list_hooks, cwds}, from, %__MODULE__{initialized?: true} = state) do
    {:noreply, request_hooks_list(state, cwds, from)}
  end

  @impl true
  def handle_call({:list_hooks, cwds}, from, %__MODULE__{active_turn: nil} = state) do
    {:noreply,
     send_request(
       state,
       "initialize",
       Protocol.initialize_request(next_id(state), @client_version),
       {:initialize_then_hooks_list, cwds, from}
     )}
  end

  @impl true
  def handle_call({:list_hooks, _cwds}, _from, state) do
    {:reply, {:error, :turn_already_active}, state}
  end

  @impl true
  def handle_call(:interrupt, _from, %__MODULE__{active_turn: nil} = state) do
    {:reply, {:error, :no_active_turn}, state}
  end

  @impl true
  def handle_call(:interrupt, _from, %__MODULE__{thread_id: nil} = state) do
    {:reply, {:error, :no_thread}, state}
  end

  @impl true
  def handle_call(:interrupt, _from, %{active_turn: %{turn_id: nil}} = state) do
    {:reply, {:error, :no_active_turn_id}, state}
  end

  @impl true
  def handle_call(:interrupt, _from, state) do
    id = next_id(state)
    request = Protocol.turn_interrupt_request(id, state.thread_id, state.active_turn.turn_id)
    emit_telemetry(:interrupt, %{}, telemetry_meta(state))
    state = send_request(state, "turn/interrupt", request, :interrupt)

    timer =
      Process.send_after(
        self(),
        {:interrupt_terminal_timeout, state.active_turn.sdk_ref},
        @cancel_terminal_timeout_ms
      )

    {:reply, :ok, put_in(state.active_turn.cancel_timer, timer)}
  end

  @impl true
  def handle_info({:request_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        {:noreply, state}

      {%{kind: kind}, pending} ->
        state = %{state | pending: pending}
        emit_telemetry(:request_timeout, %{}, telemetry_meta(state, %{kind: kind}))
        {:noreply, fail_request(kind, state, {:codex_app_server_timeout, kind})}
    end
  end

  @impl true
  def handle_info(
        {:interrupt_terminal_timeout, sdk_ref},
        %__MODULE__{active_turn: %{sdk_ref: sdk_ref}} = state
      ) do
    emit_telemetry(:cancel_timeout, %{}, telemetry_meta(state))
    {:noreply, fail_active_turn(state, :canceled)}
  end

  @impl true
  def handle_info({:interrupt_terminal_timeout, _sdk_ref}, state), do: {:noreply, state}

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %__MODULE__{port: port} = state) do
    {:noreply, handle_line(IO.iodata_to_binary(line), state)}
  end

  @impl true
  def handle_info({port, {:data, data}}, %__MODULE__{port: port} = state) do
    data = state.stdout_buffer <> IO.iodata_to_binary(data)
    {lines, rest} = split_lines(data)
    state = Enum.reduce(lines, %{state | stdout_buffer: rest}, &handle_line/2)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %__MODULE__{port: port} = state) do
    reason = {:codex_app_server_exit, status}
    emit_telemetry(:exit, %{exit_status: status}, telemetry_meta(state, %{reason: reason}))
    {:stop, reason, fail_active_turn(fail_pending(state, reason), reason)}
  end

  @impl true
  def handle_info({:codex_app_server_output, line}, state) do
    {:noreply, handle_line(line, state)}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    fail_active_turn(fail_pending(state, reason), reason)

    if is_port(state.port) do
      Port.close(state.port)
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp handle_line(line, state) do
    case Protocol.parse_line(line) do
      {:ok, {:response, response}} -> handle_response(response, state)
      {:ok, {:error, error}} -> handle_rpc_error(error, state)
      {:ok, {:notification, notification}} -> handle_notification(notification, state)
      {:ok, {:request, request}} -> handle_server_request(request, state)
      :skip -> state
      {:error, reason} -> fail_active_turn(state, {:codex_app_server_protocol_error, reason})
    end
  end

  defp handle_response(%{"id" => id, "result" => result}, state) do
    case pop_pending(state, id) do
      {%{timer: timer, kind: kind}, state} ->
        Process.cancel_timer(timer)
        handle_request_result(kind, result, state)

      {nil, state} ->
        Logger.debug("Ignoring orphan Codex app-server response id=#{inspect(id)}")
        state
    end
  end

  defp handle_rpc_error(%{"id" => id, "error" => error}, state) do
    reason = {:codex_app_server_error, error["message"] || "Codex app-server request failed"}

    case pop_pending(state, id) do
      {%{timer: timer, kind: kind}, state} ->
        Process.cancel_timer(timer)
        fail_request(kind, state, reason)

      {nil, state} ->
        Logger.debug("Ignoring orphan Codex app-server error id=#{inspect(id)}")
        fail_active_turn(state, reason)
    end
  end

  defp handle_rpc_error(%{"error" => error}, state) do
    reason = {:codex_app_server_error, error["message"] || "Codex app-server request failed"}
    fail_active_turn(state, reason)
  end

  defp handle_request_result(:initialize, _result, state) do
    write_message(state, Protocol.initialized_notification())
    state = %{state | initialized?: true}
    ensure_thread(state)
  end

  defp handle_request_result({:initialize_then_hooks_list, cwds, from}, _result, state) do
    write_message(state, Protocol.initialized_notification())
    state = %{state | initialized?: true}
    request_hooks_list(state, cwds, from)
  end

  defp handle_request_result(:thread_start, result, state) do
    case get_in(result, ["thread", "id"]) do
      thread_id when is_binary(thread_id) and thread_id != "" ->
        send(
          state.active_turn.caller_pid,
          {:codex_session_id, state.active_turn.sdk_ref, thread_id}
        )

        state = %{state | thread_id: thread_id}
        start_active_turn(state)

      _ ->
        fail_active_turn(
          state,
          {:codex_app_server_error, "thread/start response missing thread.id"}
        )
    end
  end

  defp handle_request_result(:turn_start, result, state) do
    case get_in(result, ["turn", "id"]) do
      turn_id when is_binary(turn_id) and turn_id != "" ->
        GenServer.reply(state.active_turn.from, {:ok, state.active_turn.sdk_ref, self()})
        emit_telemetry(:turn_accepted, %{}, telemetry_meta(state, %{turn_id: turn_id}))
        put_in(state.active_turn.turn_id, turn_id)

      _ ->
        fail_active_turn(state, {:codex_app_server_error, "turn/start response missing turn.id"})
    end
  end

  defp handle_request_result(:interrupt, _result, state), do: state

  defp handle_request_result({:hooks_list, from}, result, state) do
    GenServer.reply(from, {:ok, result})
    emit_telemetry(:hooks_list, %{}, telemetry_meta(state, %{hook_count: hook_count(result)}))
    state
  end

  defp ensure_thread(%__MODULE__{thread_id: thread_id} = state)
       when is_binary(thread_id) and thread_id != "" do
    start_active_turn(state)
  end

  defp ensure_thread(%__MODULE__{resume_thread_id: thread_id} = state)
       when is_binary(thread_id) and thread_id != "" do
    id = next_id(state)
    request = Protocol.thread_resume_request(id, thread_id, state.active_turn.opts)
    send_request(state, "thread/resume", request, :thread_start)
  end

  defp ensure_thread(state) do
    id = next_id(state)
    request = Protocol.thread_start_request(id, state.active_turn.opts)
    send_request(state, "thread/start", request, :thread_start)
  end

  defp start_active_turn(state) do
    id = next_id(state)

    request =
      Protocol.turn_start_request(
        id,
        state.thread_id,
        state.active_turn.prompt,
        state.active_turn.opts
      )

    send_request(state, "turn/start", request, :turn_start)
  end

  defp request_hooks_list(state, cwds, from) do
    id = next_id(state)
    request = Protocol.hooks_list_request(id, Enum.map(cwds, &Path.expand/1))
    send_request(state, "hooks/list", request, {:hooks_list, from})
  end

  defp handle_notification(%{"method" => method, "params" => params}, state)
       when is_map(params) do
    cond do
      method == "hook/started" ->
        emit_hook_telemetry(:hook_started, params, state)
        state

      method == "hook/completed" ->
        emit_hook_telemetry(:hook_completed, params, state)
        state

      method == "serverRequest/resolved" ->
        emit_server_request_resolved_telemetry(params, state)
        state

      stale_notification?(state, params) ->
        state

      method == "turn/completed" ->
        handle_turn_completed(params, state)

      true ->
        {buffer, messages} =
          TurnBuffer.apply_notification(state.active_turn.buffer, method, params)

        Enum.each(messages, &send_message(state, &1))
        put_in(state.active_turn.buffer, buffer)
    end
  end

  defp handle_notification(_notification, state), do: state

  defp handle_turn_completed(params, state) do
    turn = params["turn"] || %{}
    status = turn["status"] || params["status"] || "completed"
    error = turn["error"] || params["error"] || %{}
    duration_ms = turn["durationMs"] || params["durationMs"]
    usage = usage_from_params(params)

    {buffer, messages} = TurnBuffer.drain(state.active_turn.buffer)
    Enum.each(messages, &send_message(state, &1))

    state = put_in(state.active_turn.buffer, buffer)

    case status do
      failed when failed in ["failed", "error"] ->
        fail_active_turn(state, {:codex_turn_failed, error["message"] || "Codex turn failed"})

      canceled when canceled in ["cancelled", "canceled", "interrupted"] ->
        fail_active_turn(state, :canceled)

      _ ->
        text = TurnBuffer.result_text(state.active_turn.buffer)

        metadata = %{
          session_id: state.thread_id,
          duration_ms: duration_ms,
          usage: usage,
          input_tokens: usage["input_tokens"] || usage["inputTokens"] || 0,
          output_tokens: usage["output_tokens"] || usage["outputTokens"] || 0
        }

        send_message(state, Message.result(text || "", metadata))

        emit_telemetry(
          :turn_completed,
          %{text_length: String.length(text || "")},
          telemetry_meta(state, %{status: status})
        )

        EyeInTheSky.Claude.SDK.Registry.unregister(state.active_turn.sdk_ref)
        cancel_turn_timer(state.active_turn.cancel_timer)

        send(
          state.active_turn.caller_pid,
          {:claude_complete, state.active_turn.sdk_ref, state.thread_id}
        )

        %{state | active_turn: nil}
    end
  end

  defp handle_server_request(request, state) do
    response = Protocol.server_request_response(request)
    metadata = Protocol.server_request_metadata(request)
    write_message(state, response)

    emit_telemetry(
      :server_request_replied,
      %{},
      telemetry_meta(state, metadata)
    )

    state
  end

  defp emit_server_request_resolved_telemetry(params, state) do
    emit_telemetry(
      :server_request_resolved,
      %{},
      telemetry_meta(state, %{
        request_id: params["requestId"] || params["id"],
        thread_id: params["threadId"],
        turn_id: params["turnId"]
      })
    )
  end

  defp fail_request({:hooks_list, from}, state, reason) do
    GenServer.reply(from, {:error, reason})
    state
  end

  defp fail_request({:initialize_then_hooks_list, _cwds, from}, state, reason) do
    GenServer.reply(from, {:error, reason})
    state
  end

  defp fail_request(_kind, state, reason), do: fail_active_turn(state, reason)

  defp emit_hook_telemetry(event, params, state) do
    run = params["run"] || %{}

    metadata =
      telemetry_meta(state, %{
        hook_event_name:
          params["hookEventName"] || params["hook_event_name"] || run["eventName"] ||
            run["event_name"],
        hook_name: params["hookName"] || params["hook_name"] || run["name"] || run["hookName"],
        item_id: params["itemId"] || params["item_id"],
        exit_code:
          params["exitCode"] || params["exit_code"] || run["exitCode"] || run["exit_code"],
        trust_status: run["trustStatus"] || run["trust_status"]
      })

    emit_telemetry(event, %{}, metadata)
  end

  defp stale_notification?(%__MODULE__{active_turn: nil}, _params), do: true

  defp stale_notification?(%__MODULE__{thread_id: thread_id, active_turn: turn}, params) do
    notification_thread_id = params["threadId"]
    notification_turn_id = params["turnId"] || get_in(params, ["turn", "id"])

    (is_binary(notification_thread_id) && is_binary(thread_id) &&
       notification_thread_id != thread_id) ||
      (is_binary(notification_turn_id) &&
         is_binary(turn.turn_id) &&
         notification_turn_id != turn.turn_id)
  end

  defp usage_from_params(params) do
    params["usage"] || params["tokenUsage"] || get_in(params, ["turn", "usage"]) || %{}
  end

  defp hook_count(result) when is_map(result) do
    cond do
      is_list(result["hooks"]) -> length(result["hooks"])
      is_map(result["hooks"]) -> map_size(result["hooks"])
      is_list(result["data"]) -> result["data"] |> Enum.map(&hook_count/1) |> Enum.sum()
      true -> 0
    end
  end

  defp hook_count(_result), do: 0

  defp fail_active_turn(%__MODULE__{active_turn: nil} = state, _reason), do: state

  defp fail_active_turn(%__MODULE__{active_turn: %{terminal?: true}} = state, _reason), do: state

  defp fail_active_turn(state, reason) do
    turn = state.active_turn
    emit_terminal_failure_telemetry(state, reason)
    EyeInTheSky.Claude.SDK.Registry.unregister(turn.sdk_ref)
    cancel_turn_timer(turn.cancel_timer)
    maybe_reply_start(turn, {:error, reason})
    send(turn.caller_pid, {:claude_error, turn.sdk_ref, reason})

    %{state | active_turn: %{turn | terminal?: true}}
    |> Map.put(:active_turn, nil)
  rescue
    _ -> %{state | active_turn: nil}
  end

  defp fail_pending(state, _reason) do
    Enum.each(state.pending, fn {_id, pending} ->
      Process.cancel_timer(pending.timer)
    end)

    %{state | pending: %{}}
  end

  defp maybe_reply_start(%{turn_id: nil, from: from}, reply), do: GenServer.reply(from, reply)
  defp maybe_reply_start(_turn, _reply), do: :ok

  defp cancel_turn_timer(nil), do: :ok
  defp cancel_turn_timer(timer), do: Process.cancel_timer(timer)

  defp send_message(state, %Message{} = message) do
    send(state.active_turn.caller_pid, {:claude_message, state.active_turn.sdk_ref, message})
  end

  defp send_request(state, method, %{"id" => id} = request, kind) do
    write_message(state, request)

    timer = Process.send_after(self(), {:request_timeout, id}, @request_timeout_ms)
    pending = Map.put(state.pending, id, %{method: method, kind: kind, timer: timer})

    %{state | pending: pending, next_id: id + 1}
  end

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:eits, :codex, :app_server, event],
      Map.put_new(measurements, :system_time, System.system_time()),
      metadata
    )
  end

  defp emit_terminal_failure_telemetry(state, :canceled) do
    emit_telemetry(:turn_canceled, %{}, telemetry_meta(state, %{reason: :canceled}))
  end

  defp emit_terminal_failure_telemetry(state, {:codex_turn_failed, _message} = reason) do
    emit_telemetry(:turn_failed, %{}, telemetry_meta(state, %{reason: reason}))
  end

  defp emit_terminal_failure_telemetry(state, reason) do
    emit_telemetry(:turn_error, %{}, telemetry_meta(state, %{reason: reason}))
  end

  defp telemetry_meta(state, extra \\ %{}) do
    turn = state.active_turn || %{}

    %{
      owner_key: state.owner_key,
      thread_id: state.thread_id,
      turn_id: turn[:turn_id],
      sdk_ref: turn[:sdk_ref]
    }
    |> Map.merge(extra)
  end

  defp write_message(%__MODULE__{transport_pid: pid}, message) when is_pid(pid) do
    send(pid, {:codex_app_server_write, self(), Jason.encode!(message)})
    :ok
  end

  defp write_message(%__MODULE__{port: port}, message) when is_port(port) do
    Port.command(port, Protocol.encode!(message))
  end

  defp pop_pending(state, id) do
    {entry, pending} = Map.pop(state.pending, id)
    {entry, %{state | pending: pending}}
  end

  defp next_id(state), do: state.next_id

  defp split_lines(data) do
    parts = String.split(data, "\n")
    rest = List.last(parts) || ""
    lines = Enum.drop(parts, -1)
    {lines, rest}
  end

  defp open_transport(opts, project_path) do
    cond do
      pid = opts[:transport_pid] ->
        {:ok, %{port: nil, transport_pid: pid}}

      true ->
        with {:ok, path} <- find_codex_binary(opts) do
          port =
            Port.open({:spawn_executable, path}, [
              :binary,
              :exit_status,
              :use_stdio,
              :stderr_to_stdout,
              {:args, app_server_args(opts)},
              {:cd, project_path},
              {:env, build_env(opts)}
            ])

          {:ok, %{port: port, transport_pid: nil}}
        end
    end
  end

  defp find_codex_binary(opts) do
    cond do
      opts[:codex_executable] ->
        {:ok, opts[:codex_executable]}

      path = System.find_executable("codex") ->
        {:ok, path}

      true ->
        [
          "/usr/local/bin/codex",
          "/opt/homebrew/bin/codex",
          Path.expand("~/.local/bin/codex"),
          Path.expand("~/.cargo/bin/codex")
        ]
        |> Enum.find(&File.exists?/1)
        |> case do
          nil -> {:error, :codex_binary_not_found}
          path -> {:ok, path}
        end
    end
  end

  defp app_server_args(opts) do
    config_args =
      opts
      |> Keyword.get(:app_server_config_overrides, [])
      |> Enum.flat_map(fn override -> ["-c", to_string(override)] end)

    ["app-server"] ++ config_args ++ ["--listen", "stdio://"]
  end

  defp build_env(opts) do
    base_env =
      for {key, value} <- System.get_env(),
          value != "",
          not blocked_env_key?(key) do
        {String.to_charlist(key), String.to_charlist(value)}
      end

    base_env
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_SESSION_UUID", opts[:eits_session_uuid])
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_SESSION_ID", opts[:eits_session_id])
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_AGENT_UUID", opts[:eits_agent_uuid])
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_AGENT_ID", opts[:eits_agent_id])
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_PROJECT_ID", opts[:eits_project_id])
    |> EyeInTheSky.CLI.Port.maybe_add_env("EITS_MODEL", opts[:eits_model])
    |> EyeInTheSky.CLI.Port.maybe_add_env("ENTRYPOINT", opts[:entrypoint] || "cli")
    |> EyeInTheSky.CLI.Port.maybe_add_env("CODEX_HOME", opts[:codex_home])
    |> EyeInTheSky.CLI.Port.maybe_add_env(
      "EITS_CODEX_APP_SERVER_HOOK_LOG",
      opts[:smoke_hook_log]
    )
    |> EyeInTheSky.CLI.Port.maybe_add_env(
      "EITS_URL",
      opts[:eits_url] || System.get_env("EITS_URL", "http://localhost:5001/api/v1")
    )
    |> EyeInTheSky.CLI.Port.replace_env()
  end

  defp blocked_env_key?(key) do
    key in @blocked_env_vars or
      Enum.any?(@blocked_env_prefixes, fn prefix -> String.starts_with?(key, prefix) end)
  end
end
