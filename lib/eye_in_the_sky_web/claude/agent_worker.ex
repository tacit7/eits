defmodule EyeInTheSkyWeb.Claude.AgentWorker do
  @moduledoc """
  Persistent per-agent GenServer managing message queue and Claude lifecycle.

  One AgentWorker per session (agent). Owns the Claude CLI Port when running
  and manages a queue of pending messages. When busy, queues new messages.
  When Claude exits, processes the next queued message automatically.
  """

  use GenServer
  require Logger

  alias EyeInTheSkyWeb.Claude.Utils
  alias EyeInTheSkyWeb.Messages

  @registry EyeInTheSkyWeb.Claude.AgentRegistry

  # --- Client API ---

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    name = {:via, Registry, {@registry, {:agent, session_id}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def process_message(session_id, message, context) do
    case Registry.lookup(@registry, {:agent, session_id}) do
      [{pid, _}] -> GenServer.cast(pid, {:process_message, message, context})
      [] -> {:error, :not_found}
    end
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
    Logger.info("📨 AgentWorker.process_message: session_id=#{state.session_id}, message_length=#{String.length(message)}, has_messages=#{context.has_messages}, model=#{inspect(context.model)}")

    job = %{
      message: message,
      context: context,
      queued_at: DateTime.utc_now()
    }

    if state.port == nil do
      # Idle, spawn Claude immediately
      Logger.info("⚡ AgentWorker: spawning Claude immediately for session_id=#{state.session_id}")
      case spawn_claude(state, job) do
        {:ok, port, session_ref} ->
          Logger.info("✅ AgentWorker: Claude spawned for session_id=#{state.session_id}, port=#{inspect(port)}, ref=#{inspect(session_ref)}")
          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "agent:working",
            {:agent_working, state.session_uuid, state.session_id}
          )

          {:noreply, %{state | port: port, current_job: job, session_ref: session_ref}}

        {:error, reason} ->
          Logger.error("❌ AgentWorker: failed to spawn Claude for session_id=#{state.session_id} - #{inspect(reason)}")
          # Requeue the job instead of dropping it silently
          {:noreply, %{state | queue: state.queue ++ [job]}}
      end
    else
      # Busy, queue the job
      Logger.info("⏳ AgentWorker: busy, queueing message for session_id=#{state.session_id}, queue_length=#{length(state.queue) + 1}")
      {:noreply, %{state | queue: state.queue ++ [job]}}
    end
  end

  # Ref-guarded: only process output from the current CLI invocation
  @impl true
  def handle_info({:claude_output, ref, line}, %{session_ref: ref} = state) do
    clean_line = Utils.strip_ansi_codes(line)

    # Always log raw output at debug level so we don't miss anything
    Logger.debug("[#{state.session_id}] Raw output: #{inspect(line, limit: 500)}")

    case Jason.decode(clean_line) do
      {:ok, parsed} ->
        type = Map.get(parsed, "type") || Map.get(parsed, :type)
        subtype = Map.get(parsed, "subtype") || Map.get(parsed, :subtype)
        Logger.debug("📥 Claude output: session_id=#{state.session_id}, type=#{type}, subtype=#{inspect(subtype)}")

        try do
          handle_claude_result(parsed, state)
        rescue
          e ->
            Logger.error("❌ [#{state.session_id}] Error handling Claude result: #{inspect(e)}")
        end

      {:error, reason} ->
        # Always log non-JSON output, even if empty, as it might contain error messages
        Logger.warning("⚠️  Non-JSON output from Claude [session=#{state.session_id}]:")
        Logger.warning("   Raw: #{inspect(line, limit: 500)}")
        Logger.warning("   Cleaned: #{inspect(clean_line, limit: 500)}")
        Logger.warning("   Length: #{String.length(clean_line)} chars")
        Logger.warning("   JSON decode error: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  # Ignore output from stale CLI invocations
  @impl true
  def handle_info({:claude_output, _ref, _line}, state) do
    Logger.debug("[#{state.session_id}] Ignoring output from stale CLI ref")
    {:noreply, state}
  end

  @impl true
  def handle_info({:claude_exit, session_ref, _exit_code}, state)
      when session_ref == state.session_ref do
    # Broadcast stopped state
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "agent:working",
      {:agent_stopped, state.session_uuid, state.session_id}
    )

    # Process next job if queue not empty
    case state.queue do
      [] ->
        {:noreply, %{state | port: nil, current_job: nil, session_ref: nil}}

      [next_job | rest] ->
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
    Utils.close_port_safely(state[:port])
    :ok
  end

  # --- Private ---

  defp handle_claude_result(parsed, state) when is_map(parsed) do
    type = Map.get(parsed, "type") || Map.get(parsed, :type)

    case type do
      "result" ->
        result = Map.get(parsed, "result") || Map.get(parsed, :result)

        if result && is_binary(result) && state.session_id do
          if String.trim(result) == "[NO_RESPONSE]" do
            Logger.info("[#{state.session_id}] Agent responded with [NO_RESPONSE], skipping")
            {:ok, :no_response}
          else
            message_uuid = Map.get(parsed, "uuid") || Map.get(parsed, :uuid)
            duration_ms = Map.get(parsed, "duration_ms")
            cost = Map.get(parsed, "total_cost_usd")

            metadata = %{
              duration_ms: duration_ms,
              total_cost_usd: cost,
              usage: Map.get(parsed, "usage"),
              is_error: Map.get(parsed, "is_error")
            }

            channel_id = get_in(state, [:current_job, :context, :channel_id])

            opts = [
              source_uuid: message_uuid,
              metadata: metadata
            ]

            opts = if channel_id, do: Keyword.put(opts, :channel_id, channel_id), else: opts

            # record_incoming_reply broadcasts {:new_message} on the session topic,
            # so we do NOT broadcast again here (was causing duplicate UI events)
            case Messages.record_incoming_reply(state.session_id, "claude", result, opts) do
              {:ok, _message} ->
                {:ok, :recorded}

              {:error, reason} ->
                Logger.warning("[#{state.session_id}] DB save failed: #{inspect(reason)}")
                {:ok, :save_failed}
            end
          end
        else
          Logger.warning("[#{state.session_id}] Result has no text content")
          {:ok, :no_result}
        end

      _ ->
        {:ok, :other_type}
    end
  end

  defp spawn_claude(state, job) do
    context = job.context
    has_messages = context[:has_messages] || false
    spawn_type = if has_messages, do: :resume, else: :new
    prompt = job.message
    session_ref = make_ref()

    opts = [
      model: context[:model],
      project_path: state.project_path,
      output_format: "stream-json",
      skip_permissions: true,
      use_script: false,
      session_ref: session_ref,
      caller: self(),
      session_id: state.session_uuid,
      eits_session_id: state.session_uuid,
      eits_agent_id: state.agent_id
    ]

    opts =
      if context[:effort_level] && context[:effort_level] != "" do
        opts ++ [effort_level: context[:effort_level]]
      else
        opts
      end

    cli = Utils.cli_module()

    case spawn_type do
      :resume ->
        Logger.info("Resuming session #{state.session_uuid}")
        cli.resume_session(state.session_uuid, prompt, opts)

      :new ->
        Logger.info("Starting new session #{state.session_uuid}")
        cli.spawn_new_session(prompt, opts)
    end
  end
end
