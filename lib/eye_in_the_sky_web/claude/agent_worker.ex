defmodule EyeInTheSkyWeb.Claude.AgentWorker do
  @moduledoc """
  Persistent per-agent GenServer managing message queue and Claude lifecycle.

  One AgentWorker per session (agent). Owns the Claude CLI Port when running
  and manages a queue of pending messages. When busy, queues new messages.
  When Claude exits, processes the next queued message automatically.
  """

  use GenServer
  require Logger

  alias EyeInTheSkyWeb.Claude.SessionWorker

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
  def handle_info({:claude_output, _ref, _line}, state) do
    # Output from Claude - just log and continue
    # SessionWorker handles parsing; AgentWorker just waits for exit
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
      session_int_id: state.session_id,
      caller: self()
    ]

    # Spawn SessionWorker to handle Claude invocation and output parsing
    case DynamicSupervisor.start_child(
      EyeInTheSkyWeb.Claude.SessionSupervisor,
      {SessionWorker,
       %{
         spawn_type: spawn_type,
         session_id: state.session_uuid,
         prompt: prompt,
         opts: opts
       }}
    ) do
      {:ok, _worker_pid} ->
        Logger.info("SessionWorker spawned for #{state.session_uuid}")

        # SessionWorker spawns Claude and sends port + session_ref back to caller (self)
        # Wait to receive it
        receive do
          {:session_worker_ready, port, ^session_ref} ->
            Logger.info("Received session_worker_ready for #{state.session_uuid}")
            {:ok, port, session_ref}
        after
          5000 ->
            Logger.error("Timeout waiting for SessionWorker to spawn Claude for #{state.session_uuid}")
            {:error, :timeout}
        end

      {:error, reason} ->
        Logger.error("Failed to spawn SessionWorker: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
