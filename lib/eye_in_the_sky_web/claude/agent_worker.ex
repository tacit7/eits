defmodule EyeInTheSkyWeb.Claude.AgentWorker do
  @moduledoc """
  Persistent per-agent GenServer managing message queue and Claude lifecycle.

  One AgentWorker per session (agent). Owns the Claude CLI Port when running
  and manages a queue of pending messages. When busy, queues new messages.
  When Claude exits, processes the next queued message automatically.
  """

  use GenServer
  require Logger

  alias EyeInTheSkyWeb.Claude.CLI
  alias EyeInTheSkyWeb.Messages

  # --- Client API ---

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  def process_message(session_id, message, context) do
    GenServer.cast(via_tuple(session_id), {:process_message, message, context})
  end

  defp via_tuple(session_id) do
    {:via, Registry, {EyeInTheSkyWeb.Claude.AgentRegistry, session_id}}
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    session_uuid = Keyword.fetch!(opts, :session_uuid)
    agent_id = Keyword.fetch!(opts, :agent_id)
    project_path = Keyword.get(opts, :project_path, File.cwd!())

    state = %{
      session_id: session_id,
      session_uuid: session_uuid,
      agent_id: agent_id,
      port: nil,
      current_job: nil,
      queue: [],
      project_path: project_path,
      session_ref: nil
    }

    Logger.info("AgentWorker started for session=#{session_id} agent=#{agent_id}")

    {:ok, state}
  end

  @impl true
  def handle_cast({:process_message, message, context}, state) do
    job = %{
      message: message,
      context: context,
      queued_at: DateTime.utc_now()
    }

    if state.port == nil do
      # Idle, spawn Claude immediately
      Logger.info("Agent #{state.session_id} idle, spawning Claude")

      case spawn_claude(state, job) do
        {:ok, port, session_ref} ->
          # Broadcast working state
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "agent:working",
            {:agent_working, state.session_uuid, state.session_id}
          )

          {:noreply, %{state | port: port, current_job: job, session_ref: session_ref}}

        {:error, reason} ->
          Logger.error("Failed to spawn Claude: #{inspect(reason)}")
          {:noreply, state}
      end
    else
      # Busy, queue the job
      Logger.info("Agent #{state.session_id} busy, queueing message")
      {:noreply, %{state | queue: state.queue ++ [job]}}
    end
  end

  @impl true
  def handle_info({:claude_output, _ref, line}, state) do
    Logger.debug("Claude output: #{String.slice(line, 0..100)}...")

    # Parse and handle Claude output
    clean_line = strip_ansi_codes(line)

    case Jason.decode(clean_line) do
      {:ok, parsed} ->
        try do
          handle_claude_result(parsed, state)
        rescue
          e ->
            Logger.error("Error handling Claude result: #{inspect(e)}")
            # Still try to broadcast the result even if database save fails
            result = Map.get(parsed, "result")
            if result && is_binary(result) do
              Phoenix.PubSub.broadcast(
                EyeInTheSkyWeb.PubSub,
                "session:#{state.session_id}",
                {:new_message, %{body: result, sender_role: "agent"}}
              )
            end
        end

      {:error, reason} ->
        if String.trim(clean_line) != "" do
          Logger.debug("Non-JSON output: #{clean_line}")
        end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:claude_exit, session_ref, exit_code}, state) when session_ref == state.session_ref do
    Logger.info("Claude exited for agent #{state.session_id} (exit code: #{exit_code})")

    # Broadcast stopped state
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "agent:working",
      {:agent_stopped, state.session_uuid, state.session_id}
    )

    # Process next job if queue not empty
    case state.queue do
      [] ->
        # Queue empty, go idle
        Logger.info("Agent #{state.session_id} queue empty, going idle")
        {:noreply, %{state | port: nil, current_job: nil, session_ref: nil}}

      [next_job | rest] ->
        # Process next job
        Logger.info("Agent #{state.session_id} processing next queued job (#{length(rest)} remaining in queue)")

        case spawn_claude(state, next_job) do
          {:ok, port, session_ref} ->
            Phoenix.PubSub.broadcast(
              EyeInTheSkyWeb.PubSub,
              "agent:working",
              {:agent_working, state.session_uuid, state.session_id}
            )

            {:noreply,
             %{state | port: port, current_job: next_job, queue: rest, session_ref: session_ref}}

          {:error, reason} ->
            Logger.error("Failed to spawn Claude for next job: #{inspect(reason)}")
            # Requeue the job and go idle
            {:noreply, %{state | port: nil, current_job: nil, queue: [next_job | rest]}}
        end
    end
  end

  @impl true
  def handle_info({:claude_exit, _ref, _exit_code}, state) do
    Logger.warning("Received claude_exit for mismatched session_ref, ignoring")
    {:noreply, state}
  end

  @impl true
  def handle_info({:claude_response, _ref, _response}, state) do
    Logger.debug("Claude response received for agent #{state.session_id}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:claude_error, _ref, _error}, state) do
    Logger.warning("Claude error for agent #{state.session_id}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in AgentWorker: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
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

  defp handle_claude_result(parsed, state) when is_map(parsed) do
    type = Map.get(parsed, "type") || Map.get(parsed, :type)

    case type do
      "result" ->
        result = Map.get(parsed, "result") || Map.get(parsed, :result)

        if result && is_binary(result) && state.session_id do
          message_uuid = Map.get(parsed, "uuid") || Map.get(parsed, :uuid)

          metadata = %{
            duration_ms: Map.get(parsed, "duration_ms"),
            total_cost_usd: Map.get(parsed, "total_cost_usd"),
            usage: Map.get(parsed, "usage"),
            is_error: Map.get(parsed, "is_error")
          }

          opts = [
            source_uuid: message_uuid,
            metadata: metadata
          ]

          # Try to save to database, but don't fail if we can't (e.g., in tests with sandbox)
          case Messages.record_incoming_reply(state.session_id, "claude", result, opts) do
            {:ok, message} ->
              # Broadcast the message via PubSub
              Phoenix.PubSub.broadcast(
                EyeInTheSkyWeb.PubSub,
                "session:#{state.session_id}",
                {:new_message, message}
              )
              {:ok, message}

            {:error, _reason} ->
              # If database save fails, still broadcast via PubSub for testing
              Phoenix.PubSub.broadcast(
                EyeInTheSkyWeb.PubSub,
                "session:#{state.session_id}",
                {:new_message, %{body: result, sender_role: "agent"}}
              )
              {:ok, :broadcast_only}
          end
        else
          {:ok, :no_result}
        end

      _ ->
        {:ok, :other_type}
    end
  end

  defp handle_claude_result(_parsed, _state) do
    {:ok, :non_map}
  end

  defp strip_ansi_codes(text) when is_binary(text) do
    # Remove ANSI escape sequences
    text
    |> String.replace(~r/\e\[[0-9;]*[a-zA-Z]/, "")
    |> String.replace(~r/\e\][^\a]*\a/, "")
    |> String.replace(~r/\e[^[\\]]*/, "")
  end

  defp strip_ansi_codes(text), do: text

  defp spawn_claude(state, job) do
    context = job.context

    # Determine if resuming (has prior messages) or starting new
    has_messages = context[:has_messages] || false
    spawn_type = if has_messages, do: :resume, else: :new
    prompt = job.message

    # Generate unique session_ref for this Claude invocation
    session_ref = make_ref()

    opts = [
      model: context[:model] || "sonnet",
      project_path: state.project_path,
      output_format: "stream-json",
      skip_permissions: true,
      session_ref: session_ref,
      caller: self()
    ]

    # Spawn Claude directly and return port + session_ref
    case spawn_type do
      :resume ->
        Logger.info("Resuming session #{state.session_uuid}")
        CLI.resume_session(state.session_uuid, prompt, opts)

      :new ->
        Logger.info("Starting new session #{state.session_uuid}")
        CLI.spawn_new_session(prompt, opts)
    end
  end
end
