defmodule EyeInTheSky.Claude.AgentWorker do
  @moduledoc """
  Persistent per-agent GenServer managing message queue and Claude lifecycle.

  One AgentWorker per session (agent). Uses the Claude SDK for streaming and
  manages a queue of pending messages. When busy, queues new messages.
  When Claude completes, processes the next queued message automatically.
  """

  use GenServer, restart: :transient
  require Logger

  alias EyeInTheSky.Agents.CmdDispatcher
  alias EyeInTheSky.AgentWorkerEvents, as: WorkerEvents

  alias EyeInTheSky.Claude.AgentWorker.{
    ErrorRecovery,
    IdleTimer,
    QueueManager,
    RetryPolicy,
    SdkLifecycle,
    WatchdogTimer
  }

  alias EyeInTheSky.Claude.{Job, Message, StreamAssembler}
  alias EyeInTheSky.Claude.StreamAssemblerProtocol
  alias EyeInTheSky.Codex.StreamAssembler, as: CodexStreamAssembler
  alias EyeInTheSky.Messages

  @registry EyeInTheSky.Claude.AgentRegistry

  @type status :: :idle | :running | :retry_wait | :failed

  defstruct [
    # Internal EITS session integer PK — used for DB lookups, PubSub topics, registry key
    :session_id,
    # Internal EITS session UUID — stable identifier for this session in EITS tracking.
    # Distinct from provider_conversation_id: this never changes after the worker starts.
    :eits_session_uuid,
    # Provider conversation ID — tracks the resume key for the underlying provider:
    #   Claude: pre-generated UUID matching Claude's `--session-id` flag (stable)
    #   Codex:  starts as nil, gets synced from the Codex thread_id on thread.started
    # Use eits_session_uuid (not this field) for EITS env vars and tracking calls.
    :provider_conversation_id,
    :agent_id,
    :project_id,
    :project_path,
    :provider,
    :sdk_ref,
    :handler_monitor,
    :current_job,
    :worktree,
    :retry_timer_ref,
    :watchdog_timer_ref,
    :watchdog_run_ref,
    :handler_pid,
    :idle_timer_ref,
    status: :idle,
    queue: [],
    stream: nil,
    retry_attempt: 0
  ]

  # --- Client API ---

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    provider = Keyword.get(opts, :provider, "claude")
    # Invariant: exactly one AgentWorker per session, keyed by {:session, session_id}
    name = {:via, Registry, {@registry, {:session, session_id}, provider}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Submit a message for processing. Returns synchronous admission result:

    * `{:ok, :started}` — SDK started immediately
    * `{:ok, :queued}` — busy, message queued for later
    * `{:ok, :retry_queued}` — SDK start failed, queued for retry
    * `{:error, :queue_full}` — queue at max depth, message rejected
    * `{:error, :invalid_message}` — message was not a binary string
    * `{:error, :not_found}` — no worker registered for this session
  """
  def submit_message(session_id, message, context) do
    with_worker(
      session_id,
      fn pid ->
        GenServer.call(pid, {:submit_message, message, context})
      end,
      {:error, :not_found}
    )
  end

  def cancel(session_id) do
    with_worker(
      session_id,
      fn pid ->
        GenServer.cast(pid, :cancel)
      end,
      {:error, :not_found}
    )
  end

  def processing?(session_id) do
    with_worker(
      session_id,
      fn pid ->
        GenServer.call(pid, :processing?)
      end,
      false
    )
  end

  def get_queue(session_id) do
    with_worker(
      session_id,
      fn pid ->
        GenServer.call(pid, :get_queue)
      end,
      []
    )
  end

  def get_stream_state(session_id) do
    with_worker(
      session_id,
      fn pid ->
        GenServer.call(pid, :get_stream_state)
      end,
      ""
    )
  end

  def remove_queued_prompt(session_id, prompt_id) do
    with_worker(
      session_id,
      fn pid ->
        GenServer.cast(pid, {:remove_queued_prompt, prompt_id})
      end,
      :ok
    )
  end

  defp with_worker(session_id, fun, default) do
    case Registry.lookup(@registry, {:session, session_id}) do
      [{pid, _}] -> fun.(pid)
      [] -> default
    end
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    # eits_session_uuid: stable EITS UUID for this session, used for EITS tracking/env vars.
    # Falls back to provider_conversation_id for backward compat with callers that only pass one.
    eits_session_uuid =
      Keyword.get(opts, :eits_session_uuid) || Keyword.get(opts, :provider_conversation_id)

    provider_conversation_id = Keyword.fetch!(opts, :provider_conversation_id)
    agent_id = Keyword.fetch!(opts, :agent_id)
    project_id = Keyword.get(opts, :project_id)
    project_path = Keyword.get(opts, :project_path)
    provider = Keyword.get(opts, :provider, "claude")
    worktree = Keyword.get(opts, :worktree)

    if is_nil(project_path) do
      {:stop, :no_project_path}
    else
      state = %__MODULE__{
        session_id: session_id,
        eits_session_uuid: eits_session_uuid,
        provider_conversation_id: provider_conversation_id,
        agent_id: agent_id,
        project_id: project_id,
        project_path: project_path,
        provider: provider,
        worktree: worktree,
        stream: stream_assembler_for(provider)
      }

      Logger.info(
        "AgentWorker started for session=#{session_id} agent=#{agent_id} provider=#{provider}"
      )

      {:ok, IdleTimer.schedule(state)}
    end
  end

  @impl true
  def handle_call(:processing?, _from, state) do
    {:reply, state.status == :running, state}
  end

  @impl true
  def handle_call(:get_queue, _from, state) do
    {:reply, state.queue, state}
  end

  @impl true
  def handle_call(:get_stream_state, _from, state) do
    buf = if state.stream, do: StreamAssemblerProtocol.buffer(state.stream), else: ""
    {:reply, buf, state}
  end

  @impl true
  def handle_call({:submit_message, message, context}, _from, state) when is_binary(message) do
    {reply, new_state} = process_submit(message, Job.normalize_context(context), state)
    {:reply, reply, new_state}
  end

  @impl true
  def handle_call({:submit_message, message, _context}, _from, state) do
    Logger.warning(
      "AgentWorker.submit_message: invalid message payload for session_id=#{state.session_id} message=#{inspect(message)}"
    )

    {:reply, {:error, :invalid_message}, state}
  end

  @impl true
  def handle_cast(:cancel, %__MODULE__{status: :idle} = state) do
    {:noreply, state}
  end

  def handle_cast(:cancel, %__MODULE__{sdk_ref: ref} = state) when not is_nil(ref) do
    Logger.info("[#{state.session_id}] Cancelling SDK process (provider=#{state.provider})")
    SdkLifecycle.cancel_active_sdk(state)
    {:noreply, WatchdogTimer.cancel_watchdog(state)}
  end

  # Cancel when in retry_wait or failed with no active SDK process — reset to idle
  def handle_cast(:cancel, %__MODULE__{status: status} = state)
      when status in [:retry_wait, :failed] do
    Logger.info("[#{state.session_id}] Cancelling worker in #{status} state (no active SDK)")
    state = RetryPolicy.clear_retry_timer(state)
    {:noreply, %{state | status: :idle} |> IdleTimer.maybe_schedule()}
  end

  def handle_cast({:remove_queued_prompt, prompt_id}, state) do
    new_queue = Enum.reject(state.queue, fn %Job{id: id} -> id == prompt_id end)
    new_state = %{state | queue: new_queue}
    WorkerEvents.broadcast_queue_update(state.session_id, new_queue)
    {:noreply, new_state}
  end

  # SDK result message - contains the final response text + metadata for DB storage
  @impl true
  def handle_info(
        {:claude_message, ref, %Message{type: :result, content: text, metadata: metadata}},
        %__MODULE__{sdk_ref: ref} = state
      ) do
    channel_id = if state.current_job, do: state.current_job.context[:channel_id], else: nil

    WorkerEvents.on_result_received(state.session_id, %{
      provider: state.provider,
      text: text,
      metadata: metadata,
      channel_id: channel_id,
      source_uuid: metadata[:uuid]
    })

    result_len = if(is_binary(text), do: String.length(text), else: 0)
    emit([:eits, :agent, :result, :saved], %{text_length: result_len}, state)

    {:noreply, state}
  end

  # Tool input delta - accumulate, don't broadcast raw JSON chunk as a tool name
  @impl true
  def handle_info(
        {:claude_message, ref, %Message{type: :tool_use, delta: true, content: json}},
        %__MODULE__{sdk_ref: ref} = state
      )
      when is_binary(json) do
    {stream, _events} = StreamAssemblerProtocol.handle_tool_delta(state.stream, json)
    {:noreply, %{state | stream: stream}}
  end

  # Other SDK messages (text deltas, tool use, thinking, etc.) - broadcast for live streaming
  @impl true
  def handle_info({:claude_message, ref, %Message{} = msg}, %__MODULE__{sdk_ref: ref} = state) do
    msg = maybe_dispatch_commands(msg, state)
    {stream, events} = StreamAssemblerProtocol.handle_message(state.stream, msg)
    broadcast_events(events, state)
    {:noreply, %{state | stream: stream}}
  end

  # Tool block complete - decode accumulated input and broadcast
  @impl true
  def handle_info({:tool_block_stop, ref}, %__MODULE__{sdk_ref: ref} = state) do
    {stream, events} = StreamAssemblerProtocol.handle_tool_block_stop(state.stream)
    broadcast_events(events, state)
    {:noreply, %{state | stream: stream}}
  end

  # Stale tool_block_stop from old sdk ref - ignore
  @impl true
  def handle_info({:tool_block_stop, _ref}, state), do: {:noreply, state}

  # Codex thread_id arrived via thread.started — sync immediately so resume works
  @impl true
  def handle_info({:codex_session_id, ref, thread_id}, %__MODULE__{sdk_ref: ref} = state) do
    state = maybe_sync_provider_conversation_id(state, thread_id)
    WorkerEvents.on_codex_thread_started(state.session_id)
    {:noreply, state}
  end

  # Stale codex_session_id from old sdk ref - ignore
  @impl true
  def handle_info({:codex_session_id, _ref, _thread_id}, state), do: {:noreply, state}

  # SDK completion - process next queued job
  @impl true
  def handle_info({:claude_complete, ref, session_id}, %__MODULE__{sdk_ref: ref} = state) do
    state = maybe_sync_provider_conversation_id(state, session_id)
    WorkerEvents.broadcast_stream_clear(state.session_id)
    state = %{state | stream: StreamAssemblerProtocol.reset(state.stream)}

    Logger.info("[#{state.session_id}] SDK complete")

    emit([:eits, :agent, :sdk, :complete], %{system_time: System.system_time()}, state)

    WorkerEvents.on_sdk_completed(
      state.session_id,
      state.provider_conversation_id,
      state.provider
    )

    Messages.mark_delivered(if state.current_job, do: state.current_job.context[:message_id])

    state = WatchdogTimer.cancel_watchdog(state)
    SdkLifecycle.demonitor_handler(state.handler_monitor)

    {:noreply,
     QueueManager.process_next_job(%{
       state
       | status: :idle,
         sdk_ref: nil,
         handler_monitor: nil,
         handler_pid: nil,
         current_job: nil
     })
     |> IdleTimer.maybe_schedule()}
  end

  # Stale Claude session — retry current job as a fresh start
  @impl true
  def handle_info(
        {:claude_error, ref, {:claude_result_error, %{errors: errors}} = reason},
        %__MODULE__{sdk_ref: ref} = state
      )
      when is_list(errors) do
    ErrorRecovery.handle_stale_session(reason, state)
  end

  # Session ID already in use — either JSONL exists (no live process) or an orphaned Claude
  # process is holding the session lock. Kill any orphan, then retry as resume exactly once.
  # The :kill_retry flag prevents a second retry if the orphan kill didn't help.
  @impl true
  def handle_info(
        {:claude_error, ref, {:cli_error, msg} = reason},
        %__MODULE__{sdk_ref: ref} = state
      )
      when is_binary(msg) do
    ErrorRecovery.handle_session_in_use(reason, state)
  end

  # SDK error
  @impl true
  def handle_info({:claude_error, ref, reason}, %__MODULE__{sdk_ref: ref} = state) do
    ErrorRecovery.handle_generic_error(reason, state)
  end

  # Stale messages from previous SDK refs - ignore
  @impl true
  def handle_info({:claude_message, _ref, _msg}, state), do: {:noreply, state}

  @impl true
  def handle_info({:claude_complete, _ref, _sid}, state), do: {:noreply, state}

  @impl true
  def handle_info({:claude_error, _ref, _reason}, state), do: {:noreply, state}

  @impl true
  def handle_info(:retry_start, %__MODULE__{status: :retry_wait, queue: [_ | _]} = state) do
    {:noreply,
     QueueManager.process_next_job(%{state | status: :idle, retry_timer_ref: nil})
     |> IdleTimer.maybe_schedule()}
  end

  @impl true
  def handle_info(:retry_start, %__MODULE__{status: :retry_wait} = state) do
    {:noreply, %{state | status: :idle, retry_timer_ref: nil} |> IdleTimer.maybe_schedule()}
  end

  @impl true
  def handle_info(:retry_start, state) do
    {:noreply, state}
  end

  # Watchdog fired for the current run and worker is still :running.
  # Check handler liveness:
  # - handler alive  → legitimate slow run; rearm watchdog for same run_ref (timer already consumed)
  # - handler dead   → zombie; trigger systemic error recovery
  @impl true
  def handle_info(
        {:watchdog_check, run_ref},
        %__MODULE__{status: :running, watchdog_run_ref: run_ref} = state
      ) do
    timeout = WatchdogTimer.watchdog_timeout_ms()

    if state.handler_pid && Process.alive?(state.handler_pid) do
      Logger.warning(
        "[#{state.session_id}] Watchdog fired after #{timeout}ms but handler still alive — slow run, rearming"
      )

      {:noreply, WatchdogTimer.rearm(state, run_ref)}
    else
      Logger.error(
        "[#{state.session_id}] Watchdog fired after #{timeout}ms — handler dead, worker stuck in :running, forcing recovery"
      )

      WorkerEvents.broadcast_stream_clear(state.session_id)

      ErrorRecovery.handle_sdk_error(
        {:watchdog_timeout, timeout},
        %{
          state
          | stream: StreamAssemblerProtocol.reset(state.stream),
            watchdog_timer_ref: nil,
            watchdog_run_ref: nil
        }
      )
    end
  end

  # Stale watchdog (run_ref mismatch) or fired after worker already transitioned — ignore.
  @impl true
  def handle_info({:watchdog_check, _run_ref}, state), do: {:noreply, state}

  # Idle timeout — stop the worker to free the AgentSupervisor slot
  @impl true
  def handle_info(:idle_timeout, %__MODULE__{status: :idle, queue: []} = state) do
    Logger.info("AgentWorker: idle timeout, stopping for session_id=#{state.session_id}")
    {:stop, :normal, state}
  end

  # Raced with a new job — ignore
  def handle_info(:idle_timeout, state), do: {:noreply, state}

  # Handler process crashed — treat as SDK error so worker survives
  @impl true
  def handle_info(
        {:DOWN, monitor_ref, :process, _pid, reason},
        %__MODULE__{handler_monitor: monitor_ref, status: :running} = state
      ) do
    Logger.error("[#{state.session_id}] SDK handler crashed: #{inspect(reason)}")

    WorkerEvents.broadcast_stream_clear(state.session_id)

    ErrorRecovery.handle_sdk_error(
      {:handler_crash, reason},
      %{state | stream: StreamAssemblerProtocol.reset(state.stream), handler_monitor: nil}
    )
  end

  # Stale handler DOWN (already cleaned up) — ignore
  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in AgentWorker: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %__MODULE__{} = state) do
    SdkLifecycle.cancel_active_sdk(state)
    maybe_mark_session_failed(reason, state)
    :ok
  end

  # Normal termination (:normal, :shutdown, {:shutdown, _}) means the worker
  # completed cleanly — its callbacks already updated session status.
  # Any other reason means the worker crashed and session is now a zombie.
  defp maybe_mark_session_failed(:normal, _state), do: :ok
  defp maybe_mark_session_failed(:shutdown, _state), do: :ok
  defp maybe_mark_session_failed({:shutdown, _}, _state), do: :ok

  defp maybe_mark_session_failed(reason, %__MODULE__{session_id: session_id, provider_conversation_id: pcid}) do
    Logger.warning("AgentWorker terminating abnormally for session_id=#{session_id}: #{inspect(reason)}")

    try do
      EyeInTheSky.AgentWorkerEvents.on_session_failed(session_id, pcid)
    rescue
      e ->
        Logger.error("Failed to mark session failed on abnormal terminate: #{inspect(e)}")
    end
  end

  # --- Private ---

  # Provider-polymorphic stream assembler factory
  defp stream_assembler_for("codex"), do: CodexStreamAssembler.new()
  defp stream_assembler_for("gemini"), do: StreamAssembler.new()
  defp stream_assembler_for(_provider), do: StreamAssembler.new()

  # Recover from :failed state before processing submit
  defp process_submit(message, context, %__MODULE__{status: :failed} = state) do
    Logger.info("AgentWorker: recovering from :failed state for session_id=#{state.session_id}")
    process_submit(message, context, %{state | status: :idle, retry_attempt: 0})
  end

  # Handles the full submit_message logic; returns {reply_term, new_state}.
  # context is guaranteed to be a normalized map — Job.normalize_context/1 is called
  # in handle_call before dispatching here.
  defp process_submit(message, context, state) do
    Logger.info(
      "AgentWorker.submit_message: session_id=#{state.session_id}, " <>
        "message_length=#{String.length(message)}, has_messages=#{context.has_messages}, " <>
        "model=#{inspect(context.model)}"
    )

    state = IdleTimer.cancel(state)
    queue_len = length(state.queue)

    emit(
      [:eits, :agent, :job, :received],
      %{system_time: System.system_time()},
      %{queue_length: queue_len, has_messages: context.has_messages},
      state
    )

    job = Job.new(message, context, context[:content_blocks] || [])

    if state.status == :idle do
      QueueManager.admit_idle(state, job)
    else
      QueueManager.admit_busy(state, job)
    end
  end

  defp broadcast_events(events, state) do
    Enum.each(events, fn event ->
      EyeInTheSky.Events.stream_event(state.session_id, event)
    end)
  end

  defp maybe_dispatch_commands(%Message{type: :text, content: content} = msg, state)
       when is_binary(content) do
    case CmdDispatcher.extract_commands(content) do
      {[], _} ->
        msg

      {cmds, clean} ->
        CmdDispatcher.dispatch_all(cmds, state.session_id)
        %{msg | content: clean}
    end
  end

  defp maybe_dispatch_commands(msg, _state), do: msg

  defp maybe_sync_provider_conversation_id(state, claude_provider_conversation_id)
       when is_binary(claude_provider_conversation_id) and claude_provider_conversation_id != "" do
    if state.provider_conversation_id == claude_provider_conversation_id do
      state
    else
      WorkerEvents.on_provider_conversation_id_changed(
        state.session_id,
        state.provider_conversation_id,
        claude_provider_conversation_id
      )

      %{state | provider_conversation_id: claude_provider_conversation_id}
    end
  end

  defp maybe_sync_provider_conversation_id(state, _), do: state

  defp emit(event, measurements, state) do
    emit(event, measurements, %{}, state)
  end

  defp emit(event, measurements, extra_meta, state) do
    :telemetry.execute(event, measurements, Map.put(extra_meta, :session_id, state.session_id))
  end
end
