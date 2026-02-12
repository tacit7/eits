defmodule EyeInTheSkyWeb.Claude.SessionWorker do
  @moduledoc """
  Per-session GenServer that owns a single Claude CLI port.

  Each spawned Claude session gets its own worker process under
  DynamicSupervisor with `restart: :temporary`. The port handler
  is spawn_linked to this worker, so a handler crash only takes
  down this session, not the entire SessionManager.

  Registry provides O(1) lookup by session_ref or session_id.
  """

  use GenServer, restart: :temporary
  require Logger

  alias EyeInTheSkyWeb.Claude.CLI
  alias EyeInTheSkyWeb.Messages
  alias EyeInTheSkyWeb.Sessions
  alias EyeInTheSkyWeb.NATS.Publisher

  @registry EyeInTheSkyWeb.Claude.Registry

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

  # --- Server Callbacks ---

  @impl true
  def init(%{spawn_type: spawn_type, session_id: session_id, prompt: prompt, opts: opts}) do
    session_ref = Keyword.fetch!(opts, :session_ref)
    caller = Keyword.get(opts, :caller)

    # Register under both keys for lookup flexibility
    Registry.register(@registry, {:ref, session_ref}, session_id)
    Registry.register(@registry, {:session, session_id}, session_ref)

    # Point the handler back at this worker, not SessionManager
    opts =
      opts
      |> Keyword.put(:caller, self())
      |> Keyword.put(:session_id, session_id)

    # Get integer PK from opts if provided by caller, otherwise query database
    session_int_id =
      Keyword.get(opts, :session_int_id) ||
        case Sessions.get_session_by_uuid(session_id) do
          {:ok, session} -> session.id
          {:error, _} -> nil
        end

    case spawn_cli(spawn_type, session_id, prompt, opts) do
      {:ok, port, ^session_ref} ->
        state = %{
          session_ref: session_ref,
          session_id: session_id,
          session_int_id: session_int_id,
          port: port,
          started_at: DateTime.utc_now(),
          output_buffer: []
        }

        Logger.info("SessionWorker started for #{session_id} (ref: #{inspect(session_ref)})")

        # Send ready signal back to caller (AgentWorker)
        if caller do
          send(caller, {:session_worker_ready, port, session_ref})
        end

        # Broadcast agent working state
        Logger.info("📢 Broadcasting agent_working for session_id=#{session_id}, session_int_id=#{session_int_id}")
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "agent:working",
          {:agent_working, session_id, session_int_id}
        )

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    CLI.cancel(state.port)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      session_ref: state.session_ref,
      session_id: state.session_id,
      started_at: state.started_at,
      output_lines: length(state.output_buffer)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info({:claude_output, _ref, line}, state) do
    Logger.debug("Raw Claude line: #{line}")

    # Strip ANSI escape codes before parsing
    clean_line = strip_ansi_codes(line)

    case Jason.decode(clean_line) do
      {:ok, parsed} ->
        handle_parsed_output(parsed, state)

      {:error, reason} ->
        # Only log if it's not just empty/whitespace after stripping
        if String.trim(clean_line) != "" do
          Logger.warning("Failed to parse JSON: #{inspect(reason)} - clean line: #{clean_line}")
        end
        updated_buffer = [clean_line | state.output_buffer]
        {:noreply, %{state | output_buffer: updated_buffer}}
    end
  end

  @impl true
  def handle_info({:claude_exit, _ref, exit_code}, state) do
    Logger.info("Claude CLI session #{inspect(state.session_ref)} exited with code #{exit_code}")

    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "session:#{state.session_int_id}",
      {:claude_complete, state.session_ref, exit_code}
    )

    {:stop, :normal, state}
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
    # Broadcast agent stopped state
    if state[:session_id] && state[:session_int_id] do
      Phoenix.PubSub.broadcast(
        EyeInTheSkyWeb.PubSub,
        "agent:working",
        {:agent_stopped, state.session_id, state.session_int_id}
      )
    end

    # Defense-in-depth: close port if still open
    if state[:port] && Port.info(state.port) != nil do
      try do
        Port.close(state.port)
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  # --- Private ---

  defp spawn_cli(:new, _session_id, prompt, opts) do
    CLI.spawn_new_session(prompt, opts)
  end

  defp spawn_cli(:continue, _session_id, prompt, opts) do
    CLI.continue_session(prompt, opts)
  end

  defp spawn_cli(:resume, session_id, prompt, opts) do
    CLI.resume_session(session_id, prompt, opts)
  end

  defp handle_parsed_output(parsed, state) when is_list(parsed) do
    Logger.debug("Received list output from Claude (likely tool/system info): #{inspect(parsed)}")
    # Store in buffer but don't try to extract message content
    updated_buffer = [parsed | state.output_buffer]
    {:noreply, %{state | output_buffer: updated_buffer}}
  end

  defp handle_parsed_output(parsed, state) when is_map(parsed) do
    Logger.info("Parsed Claude output: #{inspect(parsed, pretty: true)}")

    # Get type field safely (handles both string and atom keys)
    type = Map.get(parsed, "type") || Map.get(parsed, :type)
    subtype = Map.get(parsed, "subtype") || Map.get(parsed, :subtype)

    if type == "system" && subtype == "init" do
      Logger.info("Claude init confirmed for session #{state.session_id}")
    end

    # Check for session not found error
    is_error = Map.get(parsed, "is_error") || Map.get(parsed, :is_error)
    errors = Map.get(parsed, "errors") || Map.get(parsed, :errors) || []

    if is_error && Enum.any?(errors, &String.contains?(&1, "No conversation found")) do
      Logger.error("Session not found: #{inspect(errors)} - stopping agent")
      {:stop, :session_not_found, state}
    else
      # Handle new JSON format: type="result" with structured output (includes metadata)
      result = Map.get(parsed, "result") || Map.get(parsed, :result)
      if type == "result" && result do
      content = result
      message_uuid = Map.get(parsed, "uuid") || Map.get(parsed, :uuid)

      # Extract usage metadata for chat display (handle both string and atom keys)
      metadata = %{
        duration_ms: Map.get(parsed, "duration_ms") || Map.get(parsed, :duration_ms),
        duration_api_ms: Map.get(parsed, "duration_api_ms") || Map.get(parsed, :duration_api_ms),
        num_turns: Map.get(parsed, "num_turns") || Map.get(parsed, :num_turns),
        total_cost_usd: Map.get(parsed, "total_cost_usd") || Map.get(parsed, :total_cost_usd),
        usage: Map.get(parsed, "usage") || Map.get(parsed, :usage),
        model_usage: Map.get(parsed, "modelUsage") || Map.get(parsed, :modelUsage),
        is_error: Map.get(parsed, "is_error") || Map.get(parsed, :is_error)
      }

      cost = Map.get(parsed, "total_cost_usd") || Map.get(parsed, :total_cost_usd)
      Logger.info("Result message detected - uuid: #{inspect(message_uuid)}, cost: $#{cost}")

      if content && is_binary(content) && state.session_int_id do
        session_int_id = state.session_int_id
        opts = [
          source_uuid: message_uuid,
          metadata: metadata
        ]

        case Messages.record_incoming_reply(session_int_id, "claude", content, opts) do
          {:ok, message} ->
            Publisher.publish_message(message)
            Logger.info("Recorded and published result message for session #{state.session_id}")

          {:error, reason} ->
            Logger.error(
              "Failed to record result message for session #{state.session_id}: #{inspect(reason)}"
            )
        end
      else
        Logger.warning("Result message with no valid text content: #{inspect(parsed)}")
      end
      end
    end

    # Handle legacy stream-json format for backwards compatibility
    # DISABLED: Assistant message saving skipped because result message (above) handles it
    # The result message contains both content and metadata
    role = Map.get(parsed, "role") || Map.get(parsed, :role)
    if type == "assistant" || role == "assistant" do
      Logger.debug("🔇 Assistant message detected but not saved (handled by result message)")
    end

    updated_buffer = [parsed | state.output_buffer]

    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "session:#{state.session_int_id}",
      {:claude_response, state.session_ref, parsed}
    )

    {:noreply, %{state | output_buffer: updated_buffer}}
  end

  defp extract_text_content(parsed) when is_map(parsed) do
    cond do
      message = Map.get(parsed, "message") || Map.get(parsed, :message) ->
        content_field = Map.get(message, "content") || Map.get(message, :content)
        extract_from_content_array(content_field)

      content = Map.get(parsed, "content") || Map.get(parsed, :content) ->
        extract_from_content_array(content)

      true ->
        Map.get(parsed, "text") || Map.get(parsed, :text) || Map.get(parsed, "body") || Map.get(parsed, :body)
    end
  end

  defp extract_text_content(_), do: nil

  defp extract_from_content_array(content) when is_list(content) do
    content
    |> Enum.map(fn item ->
      case item do
        %{"type" => "text", "text" => text} ->
          text

        %{"type" => "tool_use", "name" => name, "input" => input} ->
          "Using #{name} with #{inspect(input)}"

        _ ->
          nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.join("\n")
    |> case do
      "" -> nil
      text -> text
    end
  end

  defp extract_from_content_array(_), do: nil

  defp strip_ansi_codes(text) when is_binary(text) do
    # Remove ANSI escape sequences: CSI sequences (\e[...m), OSC sequences (\e]...\a), etc.
    text
    |> String.replace(~r/\e\[[0-9;]*[a-zA-Z]/, "")
    |> String.replace(~r/\e\][^\a]*\a/, "")
    |> String.replace(~r/\e[^[\]]*/, "")
  end

  defp strip_ansi_codes(text), do: text
end
