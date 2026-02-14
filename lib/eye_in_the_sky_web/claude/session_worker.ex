defmodule EyeInTheSkyWeb.Claude.SessionWorker do
  use GenServer, restart: :temporary
  require Logger

  alias EyeInTheSkyWeb.Claude.Utils
  alias EyeInTheSkyWeb.Messages
  alias EyeInTheSkyWeb.Sessions

  @registry EyeInTheSkyWeb.Claude.Registry
  @max_queue_size 5

  @moduledoc """
  Persistent per-session GenServer that owns a Claude CLI port.

  Stays alive after CLI exits (idle state). Manages a message queue
  (max #{@max_queue_size}) and processes queued messages sequentially.
  Broadcasts status changes on "session:{session_id}:status".

  Registry provides O(1) lookup by session_ref or session_id.
  """

  # --- Client API ---

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def cancel(pid) do
    GenServer.call(pid, :cancel)
  end

  def get_info(pid) do
    GenServer.call(pid, :get_info)
  end

  @doc """
  Queue a message for processing. If idle, spawns CLI immediately.
  If busy, appends to queue (max #{@max_queue_size}, drops overflow).
  """
  def queue_message(pid, prompt, opts) do
    GenServer.cast(pid, {:queue_message, prompt, opts})
  end

  # --- Server Callbacks ---

  @impl true
  def init(%{spawn_type: spawn_type, session_id: session_id, prompt: prompt, opts: opts}) do
    session_ref = Keyword.fetch!(opts, :session_ref)

    # Register under both keys for lookup flexibility
    Registry.register(@registry, {:ref, session_ref}, session_id)
    Registry.register(@registry, {:session, session_id}, session_ref)

    # Point the handler back at this worker
    opts =
      opts
      |> Keyword.put(:caller, self())
      |> Keyword.put(:session_id, session_id)

    # Resolve integer PK from sessions table for FK references (messages, etc.)
    # Wrapped in rescue for test environments without Repo
    session_int_id = resolve_session_int_id(session_id)

    case spawn_cli(spawn_type, session_id, prompt, opts) do
      {:ok, port, ^session_ref} ->
        state = %{
          session_ref: session_ref,
          session_id: session_id,
          session_int_id: session_int_id,
          port: port,
          processing: true,
          queue: [],
          started_at: DateTime.utc_now(),
          output_buffer: []
        }

        Logger.info("SessionWorker started for #{session_id}")

        broadcast_status(session_id, :working)

        if session_int_id do
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "agent:working",
            {:agent_working, session_id, session_int_id}
          )
        end

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    Utils.close_port_safely(state.port)
    broadcast_status(state.session_id, :idle)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      session_ref: state.session_ref,
      session_id: state.session_id,
      started_at: state.started_at,
      queue_depth: length(state.queue),
      processing: state.processing
    }

    {:reply, info, state}
  end

  @impl true
  def handle_cast({:queue_message, prompt, opts}, state) do
    if state.processing do
      # Busy: queue or drop
      if length(state.queue) >= @max_queue_size do
        broadcast_status(state.session_id, :queue_full)
        {:noreply, state}
      else
        {:noreply, %{state | queue: state.queue ++ [{prompt, opts}]}}
      end
    else
      # Idle: spawn CLI immediately
      case spawn_next_cli(state, prompt, opts) do
        {:ok, new_state} ->
          {:noreply, new_state}

        {:error, reason} ->
          Logger.error("[#{state.session_id}] Failed to spawn CLI: #{inspect(reason)}")
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_info({:claude_output, _ref, line}, state) do
    clean_line = Utils.strip_ansi_codes(line)

    case Jason.decode(clean_line) do
      {:ok, parsed} ->
        handle_parsed_output(parsed, state)

      {:error, _reason} ->
        if String.trim(clean_line) != "" do
          Logger.debug("Non-JSON CLI output: #{clean_line}")
        end

        {:noreply, %{state | output_buffer: [clean_line | state.output_buffer]}}
    end
  end

  @impl true
  def handle_info({:claude_exit, _ref, exit_code}, state) do
    Logger.info("Claude CLI exited with code #{exit_code} for #{state.session_id}")

    # Broadcast completion to session topic
    if state.session_int_id do
      Phoenix.PubSub.broadcast(
        EyeInTheSkyWeb.PubSub,
        "session:#{state.session_int_id}",
        {:claude_complete, state.session_ref, exit_code}
      )
    end

    # Process next queued message or go idle
    case state.queue do
      [] ->
        broadcast_status(state.session_id, :idle)

        if state.session_int_id do
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "agent:working",
            {:agent_stopped, state.session_id, state.session_int_id}
          )
        end

        {:noreply, %{state | port: nil, processing: false, session_ref: nil}}

      [{prompt, opts} | rest] ->
        case spawn_next_cli(%{state | queue: rest}, prompt, opts) do
          {:ok, new_state} ->
            {:noreply, new_state}

          {:error, reason} ->
            Logger.error("[#{state.session_id}] Failed to spawn next CLI: #{inspect(reason)}")
            broadcast_status(state.session_id, :idle)
            {:noreply, %{state | port: nil, processing: false, queue: rest, session_ref: nil}}
        end
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, state) when is_port(port) do
    Logger.warning("Unexpected port data in SessionWorker: #{inspect(data)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    Logger.warning("Port exited with status #{status}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in SessionWorker: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state[:session_id] && state[:session_int_id] do
      Phoenix.PubSub.broadcast(
        EyeInTheSkyWeb.PubSub,
        "agent:working",
        {:agent_stopped, state.session_id, state.session_int_id}
      )
    end

    Utils.close_port_safely(state[:port])
    :ok
  end

  # --- Private ---

  defp resolve_session_int_id(session_id) do
    case Sessions.get_session_by_uuid(session_id) do
      {:ok, session} -> session.id
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp spawn_next_cli(state, prompt, opts) do
    session_ref = make_ref()

    # Register new ref
    Registry.register(@registry, {:ref, session_ref}, state.session_id)

    cli_opts =
      (opts || [])
      |> Keyword.put(:caller, self())
      |> Keyword.put(:session_ref, session_ref)
      |> Keyword.put(:session_id, state.session_id)

    # Determine spawn type from opts
    spawn_type = Keyword.get(opts || [], :spawn_type, :resume)

    case spawn_cli(spawn_type, state.session_id, prompt, cli_opts) do
      {:ok, port, ^session_ref} ->
        broadcast_status(state.session_id, :working)

        if state.session_int_id do
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "agent:working",
            {:agent_working, state.session_id, state.session_int_id}
          )
        end

        {:ok,
         %{
           state
           | port: port,
             session_ref: session_ref,
             processing: true,
             output_buffer: []
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp spawn_cli(:new, _session_id, prompt, opts) do
    Utils.cli_module().spawn_new_session(prompt, opts)
  end

  defp spawn_cli(:continue, _session_id, prompt, opts) do
    Utils.cli_module().continue_session(prompt, opts)
  end

  defp spawn_cli(:resume, session_id, prompt, opts) do
    Utils.cli_module().resume_session(session_id, prompt, opts)
  end

  defp broadcast_status(session_id, status) do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "session:#{session_id}:status",
      {:session_status, session_id, status}
    )
  end

  # --- Output handling ---

  defp handle_parsed_output(parsed, state) when is_list(parsed) do
    {:noreply, %{state | output_buffer: [parsed | state.output_buffer]}}
  end

  defp handle_parsed_output(parsed, state) when is_map(parsed) do
    type = Map.get(parsed, "type") || Map.get(parsed, :type)
    subtype = Map.get(parsed, "subtype") || Map.get(parsed, :subtype)

    if type == "system" && subtype == "init" do
      Logger.info("Claude init confirmed for session #{state.session_id}")
    end

    # Check for session not found error
    is_error = Map.get(parsed, "is_error") || Map.get(parsed, :is_error)
    errors = Map.get(parsed, "errors") || Map.get(parsed, :errors) || []

    if is_error && Enum.any?(errors, &String.contains?(&1, "No conversation found")) do
      Logger.error("Session not found: #{inspect(errors)} - stopping worker")
      {:stop, :session_not_found, state}
    else
      maybe_record_result(parsed, type, state)

      updated_buffer = [parsed | state.output_buffer]

      if state.session_int_id do
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "session:#{state.session_int_id}",
          {:claude_response, state.session_ref, parsed}
        )
      end

      {:noreply, %{state | output_buffer: updated_buffer}}
    end
  end

  defp maybe_record_result(parsed, "result", state) do
    result = Map.get(parsed, "result") || Map.get(parsed, :result)

    if result && is_binary(result) && state.session_int_id do
      message_uuid = Map.get(parsed, "uuid") || Map.get(parsed, :uuid)

      metadata = %{
        duration_ms: Map.get(parsed, "duration_ms") || Map.get(parsed, :duration_ms),
        duration_api_ms: Map.get(parsed, "duration_api_ms") || Map.get(parsed, :duration_api_ms),
        num_turns: Map.get(parsed, "num_turns") || Map.get(parsed, :num_turns),
        total_cost_usd: Map.get(parsed, "total_cost_usd") || Map.get(parsed, :total_cost_usd),
        usage: Map.get(parsed, "usage") || Map.get(parsed, :usage),
        model_usage: Map.get(parsed, "modelUsage") || Map.get(parsed, :modelUsage),
        is_error: Map.get(parsed, "is_error") || Map.get(parsed, :is_error)
      }

      opts = [source_uuid: message_uuid, metadata: metadata]

      case Messages.record_incoming_reply(state.session_int_id, "claude", result, opts) do
        {:ok, _message} ->
          Logger.info("Recorded result for session #{state.session_id}")

        {:error, reason} ->
          Logger.error("Failed to record result for #{state.session_id}: #{inspect(reason)}")
      end
    end
  end

  defp maybe_record_result(_parsed, _type, _state), do: :ok
end
