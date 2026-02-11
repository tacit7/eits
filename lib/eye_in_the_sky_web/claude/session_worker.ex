defmodule EyeInTheSkyWeb.Claude.SessionWorker do
  @moduledoc """
  Per-session GenServer that owns a single Claude CLI port.

  Each spawned Claude session gets its own worker process under
  DynamicSupervisor with `restart: :temporary`. The port handler
  is spawn_linked to this worker, so a handler crash only takes
  down this session, not the entire SessionManager.

  Registry provides O(1) lookup by session_ref or session_id.

  Message queueing: If a message arrives while the worker is already
  processing, it gets queued. When the current CLI exits, the next
  queued message is processed. Max queue depth: 5.
  """

  use GenServer, restart: :temporary
  require Logger

  alias EyeInTheSkyWeb.Claude.CLI
  alias EyeInTheSkyWeb.Messages
  alias EyeInTheSkyWeb.NATS.Publisher

  # Use runtime config (not compile_env) to allow test override
  defp cli_module do
    Application.get_env(:eye_in_the_sky_web, :cli_module, EyeInTheSkyWeb.Claude.CLI)
  end
  @registry EyeInTheSkyWeb.Claude.Registry
  @max_queue 5
  @idle_timeout :timer.seconds(60)

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

    # Register under both keys for lookup flexibility
    Registry.register(@registry, {:ref, session_ref}, session_id)
    Registry.register(@registry, {:session, session_id}, session_ref)

    # Point the handler back at this worker, not SessionManager
    opts =
      opts
      |> Keyword.put(:caller, self())
      |> Keyword.put(:session_id, session_id)

    Logger.info("SessionWorker.init: spawn_type=#{spawn_type} session=#{session_id}")
    Logger.info("SessionWorker.init: prompt=#{String.slice(prompt, 0, 200)}")

    case spawn_cli(spawn_type, session_id, prompt, opts) do
      {:ok, port, ^session_ref} ->
        state = %{
          session_ref: session_ref,
          session_id: session_id,
          port: port,
          started_at: DateTime.utc_now(),
          output_buffer: [],
          message_queue: :queue.new(),
          processing: true
        }

        broadcast_status(session_id, :working)
        Logger.info("SessionWorker started for #{session_id} port=#{inspect(port)}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("SessionWorker.init FAILED for #{session_id}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:cancel, _from, state) do
    cli_module().cancel(state.port)
    broadcast_status(state.session_id, :idle)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      session_ref: state.session_ref,
      session_id: state.session_id,
      started_at: state.started_at,
      output_lines: length(state.output_buffer),
      queue_depth: :queue.len(state.message_queue),
      processing: state.processing
    }

    {:reply, info, state}
  end

  # Enqueue a message from SessionManager dedup
  @impl true
  def handle_cast({:enqueue_message, prompt, opts}, state) do
    cond do
      :queue.len(state.message_queue) >= @max_queue ->
        Logger.warning("Queue full for session #{state.session_id}, dropping message")
        broadcast_status(state.session_id, :queue_full)
        {:noreply, state}

      !state.processing ->
        # Idle worker, process immediately
        broadcast_status(state.session_id, :working)

        case spawn_next_message(prompt, opts, state) do
          {:ok, new_state} ->
            {:noreply, new_state}

          {:error, reason} ->
            Logger.error("Failed to resume session #{state.session_id}: #{inspect(reason)}")
            broadcast_status(state.session_id, :error)
            {:noreply, state, @idle_timeout}
        end

      true ->
        # Currently processing, queue it
        new_queue = :queue.in({prompt, opts}, state.message_queue)
        Logger.info("Queued message for #{state.session_id} (depth: #{:queue.len(new_queue)})")
        {:noreply, %{state | message_queue: new_queue}}
    end
  end

  @impl true
  def handle_info({:claude_output, _ref, line}, state) do
    Logger.debug("Raw Claude line: #{line}")

    case Jason.decode(line) do
      {:ok, parsed} ->
        handle_parsed_output(parsed, state)

      {:error, reason} ->
        Logger.warning("Failed to parse JSON: #{inspect(reason)} - line: #{line}")
        updated_buffer = [line | state.output_buffer]
        {:noreply, %{state | output_buffer: updated_buffer}}
    end
  end

  @impl true
  def handle_info({:claude_exit, _ref, exit_code}, state) do
    Logger.info("Claude CLI session #{inspect(state.session_ref)} exited with code #{exit_code}")

    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "session:#{state.session_id}",
      {:claude_complete, state.session_ref, exit_code}
    )

    # Check queue for next message
    case :queue.out(state.message_queue) do
      {{:value, {prompt, opts}}, new_queue} ->
        Logger.info("Processing next queued message for #{state.session_id}")

        case spawn_next_message(prompt, opts, %{state | message_queue: new_queue}) do
          {:ok, new_state} ->
            {:noreply, new_state}

          {:error, reason} ->
            Logger.error("Failed to process queued message: #{inspect(reason)}")
            broadcast_status(state.session_id, :error)
            {:stop, :normal, state}
        end

      {:empty, _} ->
        broadcast_status(state.session_id, :idle)
        {:noreply, %{state | processing: false, port: nil}, @idle_timeout}
    end
  end

  # Idle timeout - stop worker after inactivity
  @impl true
  def handle_info(:timeout, state) do
    if state.processing do
      {:noreply, state}
    else
      Logger.info("SessionWorker idle timeout for #{state.session_id}, stopping")
      {:stop, :normal, state}
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
    broadcast_status(state.session_id, :idle)

    # Defense-in-depth: close port if still open
    # In tests, port might be a PID (mock), so check if it's actually a port
    if state[:port] && is_port(state.port) && Port.info(state.port) != nil do
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
    cli_module().spawn_new_session(prompt, opts)
  end

  defp spawn_cli(:continue, _session_id, prompt, opts) do
    cli_module().continue_session(prompt, opts)
  end

  defp spawn_cli(:resume, session_id, prompt, opts) do
    cli_module().resume_session(session_id, prompt, opts)
  end

  defp spawn_next_message(prompt, opts, state) do
    session_ref = make_ref()

    opts =
      opts
      |> Keyword.put(:caller, self())
      |> Keyword.put(:session_id, state.session_id)
      |> Keyword.put(:session_ref, session_ref)

    case spawn_cli(:resume, state.session_id, prompt, opts) do
      {:ok, port, ^session_ref} ->
        Registry.register(@registry, {:ref, session_ref}, state.session_id)
        broadcast_status(state.session_id, :working)
        {:ok, %{state | port: port, session_ref: session_ref, processing: true}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp broadcast_status(session_id, status) do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "session:#{session_id}:status",
      {:session_status, session_id, status}
    )
  end

  defp handle_parsed_output(parsed, state) do
    Logger.info("Parsed Claude output: #{inspect(parsed, pretty: true)}")

    if parsed["type"] == "system" && parsed["subtype"] == "init" do
      Logger.info("Claude init confirmed for session #{state.session_id}")
    end

    if parsed["type"] == "assistant" || parsed["role"] == "assistant" do
      content = extract_text_content(parsed)
      message_uuid = parsed["uuid"]
      Logger.info("Assistant message detected - uuid: #{inspect(message_uuid)}, content: #{inspect(content)}")

      if content && is_binary(content) do
        session_uuid = state.session_id
        opts = if message_uuid, do: [source_uuid: message_uuid], else: []

        Task.Supervisor.start_child(EyeInTheSkyWeb.TaskSupervisor, fn ->
          # Look up integer session ID from UUID
          case EyeInTheSkyWeb.Sessions.get_session_by_uuid(session_uuid) do
            {:ok, session} ->
              case Messages.record_incoming_reply(session.id, "claude", content, opts) do
                {:ok, message} ->
                  Publisher.publish_message(message)
                  Logger.info("Recorded and published assistant message for session #{session_uuid}")

                {:error, reason} ->
                  Logger.error(
                    "Failed to record assistant message for session #{session_uuid}: #{inspect(reason)}"
                  )
              end

            {:error, :not_found} ->
              Logger.error("Session not found for UUID #{session_uuid}, cannot record message")
          end
        end)
      else
        Logger.warning("Assistant message with no valid text content: #{inspect(parsed)}")
      end
    end

    updated_buffer = [parsed | state.output_buffer]

    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "session:#{state.session_id}",
      {:claude_response, state.session_ref, parsed}
    )

    {:noreply, %{state | output_buffer: updated_buffer}}
  end

  defp extract_text_content(parsed) do
    cond do
      message = parsed["message"] ->
        extract_from_content_array(message["content"])

      content = parsed["content"] ->
        extract_from_content_array(content)

      true ->
        parsed["text"] || parsed["body"]
    end
  end

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
end
