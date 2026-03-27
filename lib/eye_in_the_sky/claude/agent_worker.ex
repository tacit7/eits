defmodule EyeInTheSky.Claude.AgentWorker do
  @moduledoc """
  Persistent per-agent GenServer managing message queue and Claude lifecycle.

  One AgentWorker per session (agent). Uses the Claude SDK for streaming and
  manages a queue of pending messages. When busy, queues new messages.
  When Claude completes, processes the next queued message automatically.
  """

  use GenServer, restart: :transient
  require Logger

  alias EyeInTheSky.Claude.{Job, Message, ProviderStrategy, StreamAssembler}
  alias EyeInTheSky.Claude.StreamAssemblerProtocol
  alias EyeInTheSky.Codex.StreamAssembler, as: CodexStreamAssembler
  alias EyeInTheSky.AgentWorkerEvents, as: WorkerEvents
  alias EyeInTheSky.Agents.CmdDispatcher

  @registry EyeInTheSky.Claude.AgentRegistry
  @retry_start_ms 1_000
  @retry_max_ms 30_000
  @max_queue_depth 5
  @max_retries 5

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

  def is_processing?(session_id) do
    with_worker(
      session_id,
      fn pid ->
        GenServer.call(pid, :is_processing?)
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
    project_path = Keyword.get(opts, :project_path, File.cwd!())
    provider = Keyword.get(opts, :provider, "claude")
    worktree = Keyword.get(opts, :worktree)

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

    {:ok, state}
  end

  @impl true
  def handle_call(:is_processing?, _from, state) do
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
    {reply, new_state} = process_submit(message, context, state)
    {:reply, reply, new_state}
  end

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
    strategy = ProviderStrategy.for_provider(state.provider)
    strategy.cancel(ref)
    {:noreply, state}
  end

  # Cancel when in retry_wait or failed with no active SDK process — reset to idle
  def handle_cast(:cancel, %__MODULE__{status: status} = state)
      when status in [:retry_wait, :failed] do
    Logger.info("[#{state.session_id}] Cancelling worker in #{status} state (no active SDK)")
    state = clear_retry_timer(state)
    {:noreply, %{state | status: :idle}}
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
    WorkerEvents.on_result_received(state.session_id, state.provider, text, metadata, channel_id)

    result_len = if(is_binary(text), do: String.length(text), else: 0)

    :telemetry.execute(
      [:eits, :agent, :result, :saved],
      %{
        text_length: result_len
      },
      %{session_id: state.session_id}
    )

    Logger.info(
      "[telemetry] agent.result.saved session_id=#{state.session_id} text_length=#{result_len}"
    )

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

    :telemetry.execute([:eits, :agent, :sdk, :complete], %{system_time: System.system_time()}, %{
      session_id: state.session_id
    })

    Logger.info("[telemetry] agent.sdk.complete session_id=#{state.session_id}")

    WorkerEvents.on_sdk_completed(state.session_id, state.provider_conversation_id, state.provider)

    demonitor_handler(state.handler_monitor)

    process_next_job(%{
      state
      | status: :idle,
        sdk_ref: nil,
        handler_monitor: nil,
        current_job: nil
    })
  end

  # Stale Claude session — retry current job as a fresh start
  @impl true
  def handle_info(
        {:claude_error, ref, {:claude_result_error, %{errors: errors}} = reason},
        %__MODULE__{sdk_ref: ref, current_job: job} = state
      )
      when is_list(errors) do
    WorkerEvents.broadcast_stream_clear(state.session_id)
    state = %{state | stream: StreamAssemblerProtocol.reset(state.stream)}

    if Enum.any?(errors, &String.contains?(&1, "No conversation found")) && not is_nil(job) do
      Logger.warning(
        "[#{state.session_id}] Stale Claude session UUID=#{state.provider_conversation_id}, retrying as new session"
      )

      fresh_job = Job.as_fresh_session(job)

      case start_sdk(state, fresh_job) do
        {:ok, sdk_ref, handler_monitor} ->
          {:noreply,
           %{state | sdk_ref: sdk_ref, handler_monitor: handler_monitor, current_job: fresh_job}}

        {:error, start_reason} ->
          Logger.error(
            "[#{state.session_id}] Failed to restart fresh SDK: #{inspect(start_reason)}"
          )

          WorkerEvents.on_sdk_errored(state.session_id, state.provider_conversation_id)
          demonitor_handler(state.handler_monitor)

          process_next_job(%{
            state
            | status: :idle,
              sdk_ref: nil,
              handler_monitor: nil,
              current_job: nil
          })
      end
    else
      do_handle_sdk_error(reason, state)
    end
  end

  # SDK error
  @impl true
  def handle_info({:claude_error, ref, reason}, %__MODULE__{sdk_ref: ref} = state) do
    WorkerEvents.broadcast_stream_clear(state.session_id)
    do_handle_sdk_error(reason, %{state | stream: StreamAssemblerProtocol.reset(state.stream)})
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
    process_next_job(%{state | status: :idle, retry_timer_ref: nil})
  end

  @impl true
  def handle_info(:retry_start, %__MODULE__{status: :retry_wait} = state) do
    {:noreply, %{state | status: :idle, retry_timer_ref: nil}}
  end

  @impl true
  def handle_info(:retry_start, state) do
    {:noreply, state}
  end

  # Handler process crashed — treat as SDK error so worker survives
  @impl true
  def handle_info(
        {:DOWN, monitor_ref, :process, _pid, reason},
        %__MODULE__{handler_monitor: monitor_ref, status: :running} = state
      ) do
    Logger.error("[#{state.session_id}] SDK handler crashed: #{inspect(reason)}")

    WorkerEvents.broadcast_stream_clear(state.session_id)

    do_handle_sdk_error(
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
  def terminate(_reason, %__MODULE__{} = state) do
    if state.sdk_ref do
      strategy = ProviderStrategy.for_provider(state.provider || "claude")
      strategy.cancel(state.sdk_ref)
    end

    :ok
  end

  # --- Private ---

  # Provider-polymorphic stream assembler factory
  defp stream_assembler_for("codex"), do: CodexStreamAssembler.new()
  defp stream_assembler_for(_provider), do: StreamAssembler.new()

  # Recover from :failed state before processing submit
  defp process_submit(message, context, %__MODULE__{status: :failed} = state) do
    Logger.info("AgentWorker: recovering from :failed state for session_id=#{state.session_id}")
    process_submit(message, context, %{state | status: :idle, retry_attempt: 0})
  end

  # Handles the full submit_message logic; returns {reply_term, new_state}.
  defp process_submit(message, context, state) do
    context = normalize_context(context)

    Logger.info(
      "AgentWorker.submit_message: session_id=#{state.session_id}, " <>
        "message_length=#{String.length(message)}, has_messages=#{context.has_messages}, " <>
        "model=#{inspect(context.model)}"
    )

    queue_len = length(state.queue)

    :telemetry.execute([:eits, :agent, :job, :received], %{system_time: System.system_time()}, %{
      session_id: state.session_id,
      queue_length: queue_len,
      has_messages: context.has_messages
    })

    job = Job.new(message, context, context[:content_blocks] || [])

    if state.status == :idle do
      Logger.info("AgentWorker: starting SDK for session_id=#{state.session_id}")

      case start_sdk(state, job) do
        {:ok, sdk_ref, handler_monitor} ->
          Logger.info("AgentWorker: SDK started for session_id=#{state.session_id}")

          :telemetry.execute(
            [:eits, :agent, :job, :started],
            %{system_time: System.system_time()},
            %{session_id: state.session_id}
          )

          WorkerEvents.on_sdk_started(state.session_id, state.provider_conversation_id)

          {{:ok, :started},
           clear_retry_timer(%{
             state
             | status: :running,
               sdk_ref: sdk_ref,
               handler_monitor: handler_monitor,
               current_job: job
           })}

        {:error, reason} ->
          reason_str = inspect(reason)

          Logger.error(
            "AgentWorker: failed to start SDK for session_id=#{state.session_id} - #{reason_str}"
          )

          WorkerEvents.on_spawn_error(state.session_id, reason)

          {{:ok, :retry_queued}, state |> enqueue_job(job) |> schedule_retry_start()}
      end
    else
      if length(state.queue) >= @max_queue_depth do
        Logger.warning(
          "AgentWorker: queue full (#{@max_queue_depth}) for session_id=#{state.session_id}, rejecting message"
        )

        {{:error, :queue_full}, state}
      else
        new_queue_length = length(state.queue) + 1

        Logger.info(
          "AgentWorker: busy, queueing message for session_id=#{state.session_id}, " <>
            "queue_length=#{new_queue_length}"
        )

        :telemetry.execute([:eits, :agent, :job, :queued], %{queue_length: new_queue_length}, %{
          session_id: state.session_id
        })

        {{:ok, :queued}, enqueue_job(state, job)}
      end
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
      {[], _} -> msg
      {cmds, clean} ->
        CmdDispatcher.dispatch_all(cmds, state.session_id)
        %{msg | content: clean}
    end
  end

  defp maybe_dispatch_commands(msg, _state), do: msg

  defp process_next_job(%__MODULE__{queue: []} = state) do
    WorkerEvents.broadcast_queue_update(state.session_id, state.queue)
    {:noreply, state}
  end

  defp process_next_job(%__MODULE__{queue: [next_job | rest]} = state) do
    case start_sdk(state, next_job) do
      {:ok, sdk_ref, handler_monitor} ->
        WorkerEvents.on_sdk_started(state.session_id, state.provider_conversation_id)

        new_state =
          clear_retry_timer(%{
            state
            | status: :running,
              sdk_ref: sdk_ref,
              handler_monitor: handler_monitor,
              current_job: next_job,
              queue: rest
          })

        WorkerEvents.broadcast_queue_update(state.session_id, new_state.queue)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to start SDK for next job: #{inspect(reason)}")
        {:noreply, %{state | queue: [next_job | rest]} |> schedule_retry_start()}
    end
  end

  defp start_sdk(%__MODULE__{} = state, job) do
    strategy = ProviderStrategy.for_provider(state.provider)
    has_messages = job.context[:has_messages] || false

    result =
      if has_messages do
        strategy.resume(state, job)
      else
        strategy.start(state, job)
      end

    monitor_handler(result)
  end

  # Convert {:ok, sdk_ref, handler_pid} to {:ok, sdk_ref, monitor_ref}
  defp monitor_handler({:ok, sdk_ref, handler_pid}) do
    monitor_ref = Process.monitor(handler_pid)
    {:ok, sdk_ref, monitor_ref}
  end

  defp monitor_handler({:error, _} = error), do: error

  defp demonitor_handler(nil), do: :ok
  defp demonitor_handler(ref), do: Process.demonitor(ref, [:flush])

  defp enqueue_job(state, %Job{} = job) do
    job = Job.assign_id(job)
    new_queue = state.queue ++ [job]
    new_state = %{state | queue: new_queue}
    WorkerEvents.broadcast_queue_update(state.session_id, new_queue)
    new_state
  end

  defp schedule_retry_start(%__MODULE__{retry_timer_ref: nil, retry_attempt: attempt} = state)
       when attempt >= @max_retries do
    Logger.error("[#{state.session_id}] Max retries (#{@max_retries}) exceeded, giving up")

    WorkerEvents.on_max_retries_exceeded(state.session_id, state.provider_conversation_id)
    WorkerEvents.broadcast_queue_update(state.session_id, [])

    %{state | status: :failed, queue: [], retry_attempt: 0}
  end

  defp schedule_retry_start(%__MODULE__{retry_timer_ref: nil} = state) do
    delay = min(round(@retry_start_ms * :math.pow(2, state.retry_attempt)), @retry_max_ms)

    Logger.info(
      "[#{state.session_id}] Scheduling retry in #{delay}ms (attempt=#{state.retry_attempt})"
    )

    timer_ref = Process.send_after(self(), :retry_start, delay)

    %{
      state
      | status: :retry_wait,
        retry_timer_ref: timer_ref,
        retry_attempt: state.retry_attempt + 1
    }
  end

  defp schedule_retry_start(state), do: state

  defp clear_retry_timer(%__MODULE__{retry_timer_ref: nil} = state),
    do: %{state | retry_attempt: 0}

  defp clear_retry_timer(state) do
    Process.cancel_timer(state.retry_timer_ref)
    %{state | retry_timer_ref: nil, retry_attempt: 0}
  end

  defp normalize_context(context) when is_map(context) do
    %{
      model: Map.get(context, :model),
      effort_level: Map.get(context, :effort_level),
      has_messages: Map.get(context, :has_messages, false),
      channel_id: Map.get(context, :channel_id),
      thinking_budget: Map.get(context, :thinking_budget),
      max_budget_usd: Map.get(context, :max_budget_usd),
      agent: Map.get(context, :agent),
      eits_workflow: Map.get(context, :eits_workflow, "1"),
      bypass_sandbox: Map.get(context, :bypass_sandbox, false),
      content_blocks: Map.get(context, :content_blocks, []),
      extra_cli_opts: Map.get(context, :extra_cli_opts, [])
    }
  end

  defp normalize_context(context) when is_list(context) do
    %{
      model: context[:model],
      effort_level: context[:effort_level],
      has_messages: context[:has_messages] || false,
      channel_id: context[:channel_id],
      thinking_budget: context[:thinking_budget],
      max_budget_usd: context[:max_budget_usd],
      agent: context[:agent],
      eits_workflow: context[:eits_workflow] || "1",
      bypass_sandbox: context[:bypass_sandbox] || false,
      content_blocks: context[:content_blocks] || [],
      extra_cli_opts: context[:extra_cli_opts] || []
    }
  end

  defp normalize_context(_context) do
    %{
      model: nil,
      effort_level: nil,
      has_messages: false,
      channel_id: nil,
      thinking_budget: nil,
      max_budget_usd: nil,
      agent: nil,
      eits_workflow: "1",
      content_blocks: [],
      extra_cli_opts: []
    }
  end

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

  defp do_handle_sdk_error(reason, state) do
    Logger.error("[#{state.session_id}] SDK error: #{inspect(reason)}")

    :telemetry.execute([:eits, :agent, :sdk, :error], %{system_time: System.system_time()}, %{
      session_id: state.session_id,
      reason: reason
    })

    WorkerEvents.on_sdk_errored(state.session_id, state.provider_conversation_id)
    demonitor_handler(state.handler_monitor)

    if systemic_error?(reason) do
      WorkerEvents.on_queue_drained(
        state.session_id,
        state.provider_conversation_id,
        state.queue,
        reason
      )

      WorkerEvents.broadcast_queue_update(state.session_id, [])

      {:noreply,
       %{state | status: :failed, sdk_ref: nil, handler_monitor: nil, current_job: nil, queue: []}}
    else
      process_next_job(%{
        state
        | status: :idle,
          sdk_ref: nil,
          handler_monitor: nil,
          current_job: nil
      })
    end
  end

  defp systemic_error?(reason) do
    reason_str = inspect(reason)

    Enum.any?(
      ["billing_error", "auth_error", "missing binary", "Credit balance is too low"],
      &String.contains?(reason_str, &1)
    )
  end
end
