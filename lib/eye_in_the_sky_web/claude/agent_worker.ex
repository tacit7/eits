defmodule EyeInTheSkyWeb.Claude.AgentWorker do
  @moduledoc """
  Persistent per-agent GenServer managing message queue and Claude lifecycle.

  One AgentWorker per session (agent). Uses the Claude SDK for streaming and
  manages a queue of pending messages. When busy, queues new messages.
  When Claude completes, processes the next queued message automatically.
  """

  use GenServer, restart: :transient
  require Logger

  alias EyeInTheSkyWeb.Claude.{Job, Message, SDK, StreamAssembler, WorkerEvents}
  alias EyeInTheSkyWeb.Codex

  @registry EyeInTheSkyWeb.Claude.AgentRegistry
  @retry_start_ms 1_000
  @retry_max_ms 30_000
  @max_queue_depth 5
  @max_retries 5

  @type status :: :idle | :running | :retry_wait | :failed

  defstruct [
    :session_id,
    :provider_conversation_id,
    :agent_id,
    :project_path,
    :provider,
    :sdk_ref,
    :handler_monitor,
    :current_job,
    :worktree,
    :retry_timer_ref,
    status: :idle,
    queue: [],
    stream: %StreamAssembler{},
    retry_attempt: 0
  ]

  # --- Client API ---

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    provider = Keyword.get(opts, :provider, "claude")
    name = {:via, Registry, {@registry, {:agent, session_id}, provider}}
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
    with_worker(session_id, fn pid ->
      GenServer.call(pid, {:submit_message, message, context})
    end, {:error, :not_found})
  end

  def cancel(session_id) do
    with_worker(session_id, fn pid ->
      GenServer.cast(pid, :cancel)
    end, {:error, :not_found})
  end

  def is_processing?(session_id) do
    with_worker(session_id, fn pid ->
      GenServer.call(pid, :is_processing?)
    end, false)
  end

  def get_queue(session_id) do
    with_worker(session_id, fn pid ->
      GenServer.call(pid, :get_queue)
    end, [])
  end

  def get_stream_state(session_id) do
    with_worker(session_id, fn pid ->
      GenServer.call(pid, :get_stream_state)
    end, "")
  end

  def remove_queued_prompt(session_id, prompt_id) do
    with_worker(session_id, fn pid ->
      GenServer.cast(pid, {:remove_queued_prompt, prompt_id})
    end, :ok)
  end

  defp with_worker(session_id, fun, default) do
    case Registry.lookup(@registry, {:agent, session_id}) do
      [{pid, _}] -> fun.(pid)
      [] -> default
    end
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    provider_conversation_id = Keyword.fetch!(opts, :provider_conversation_id)
    agent_id = Keyword.fetch!(opts, :agent_id)
    project_path = Keyword.get(opts, :project_path, File.cwd!())
    provider = Keyword.get(opts, :provider, "claude")
    worktree = Keyword.get(opts, :worktree)

    state = %__MODULE__{
      session_id: session_id,
      provider_conversation_id: provider_conversation_id,
      agent_id: agent_id,
      project_path: project_path,
      provider: provider,
      worktree: worktree
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
    {:reply, StreamAssembler.buffer(state.stream), state}
  end

  @impl true
  def handle_call({:submit_message, message, context}, _from, state) when is_binary(message) do
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

    job = Job.new(message, context)

    # Recover from :failed state — reset so we can attempt to start the SDK again
    state =
      if state.status == :failed do
        Logger.info(
          "AgentWorker: recovering from :failed state for session_id=#{state.session_id}"
        )

        %{state | status: :idle, retry_attempt: 0}
      else
        state
      end

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

          {:reply, {:ok, :started},
           clear_retry_timer(%{state | status: :running, sdk_ref: sdk_ref, handler_monitor: handler_monitor, current_job: job})}

        {:error, reason} ->
          reason_str = inspect(reason)

          Logger.error(
            "AgentWorker: failed to start SDK for session_id=#{state.session_id} - #{reason_str}"
          )

          WorkerEvents.on_spawn_error(state.session_id, reason)

          {:reply, {:ok, :retry_queued}, state |> enqueue_job(job) |> schedule_retry_start()}
      end
    else
      if length(state.queue) >= @max_queue_depth do
        Logger.warning(
          "AgentWorker: queue full (#{@max_queue_depth}) for session_id=#{state.session_id}, rejecting message"
        )

        {:reply, {:error, :queue_full}, state}
      else
        new_queue_length = length(state.queue) + 1

        Logger.info(
          "AgentWorker: busy, queueing message for session_id=#{state.session_id}, " <>
            "queue_length=#{new_queue_length}"
        )

        :telemetry.execute([:eits, :agent, :job, :queued], %{queue_length: new_queue_length}, %{
          session_id: state.session_id
        })

        {:reply, {:ok, :queued}, enqueue_job(state, job)}
      end
    end
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
    cancel_sdk(state.provider, ref)
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
    {stream, _events} = StreamAssembler.handle_tool_delta(state.stream, json)
    {:noreply, %{state | stream: stream}}
  end

  # Other SDK messages (text deltas, tool use, thinking, etc.) - broadcast for live streaming
  @impl true
  def handle_info({:claude_message, ref, %Message{} = msg}, %__MODULE__{sdk_ref: ref} = state) do
    {stream, events} = StreamAssembler.handle_message(state.stream, msg)
    broadcast_events(events, state)
    {:noreply, %{state | stream: stream}}
  end

  # Tool block complete - decode accumulated input and broadcast
  @impl true
  def handle_info({:tool_block_stop, ref}, %__MODULE__{sdk_ref: ref} = state) do
    {stream, events} = StreamAssembler.handle_tool_block_stop(state.stream)
    broadcast_events(events, state)
    {:noreply, %{state | stream: stream}}
  end

  # Stale tool_block_stop from old sdk ref - ignore
  @impl true
  def handle_info({:tool_block_stop, _ref}, state), do: {:noreply, state}

  # SDK completion - process next queued job
  @impl true
  def handle_info({:claude_complete, ref, session_id}, %__MODULE__{sdk_ref: ref} = state) do
    state = maybe_sync_provider_conversation_id(state, session_id)
    WorkerEvents.broadcast_stream_clear(state.session_id)
    state = %{state | stream: StreamAssembler.reset(state.stream)}

    Logger.info("[#{state.session_id}] SDK complete")

    :telemetry.execute([:eits, :agent, :sdk, :complete], %{system_time: System.system_time()}, %{
      session_id: state.session_id
    })

    Logger.info("[telemetry] agent.sdk.complete session_id=#{state.session_id}")

    WorkerEvents.on_sdk_completed(state.session_id, state.provider_conversation_id)

    demonitor_handler(state.handler_monitor)
    process_next_job(%{state | status: :idle, sdk_ref: nil, handler_monitor: nil, current_job: nil})
  end

  # Stale Claude session — retry current job as a fresh start
  @impl true
  def handle_info(
        {:claude_error, ref, {:claude_result_error, %{errors: errors}} = reason},
        %__MODULE__{sdk_ref: ref, current_job: job} = state
      )
      when is_list(errors) do
    WorkerEvents.broadcast_stream_clear(state.session_id)
    state = %{state | stream: StreamAssembler.reset(state.stream)}

    if Enum.any?(errors, &String.contains?(&1, "No conversation found")) && not is_nil(job) do
      Logger.warning(
        "[#{state.session_id}] Stale Claude session UUID=#{state.provider_conversation_id}, retrying as new session"
      )

      fresh_job = Job.as_fresh_session(job)

      case start_sdk(state, fresh_job) do
        {:ok, sdk_ref, handler_monitor} ->
          {:noreply, %{state | sdk_ref: sdk_ref, handler_monitor: handler_monitor, current_job: fresh_job}}

        {:error, start_reason} ->
          Logger.error(
            "[#{state.session_id}] Failed to restart fresh SDK: #{inspect(start_reason)}"
          )

          WorkerEvents.on_sdk_errored(state.session_id, state.provider_conversation_id)
          demonitor_handler(state.handler_monitor)

          process_next_job(%{state | status: :idle, sdk_ref: nil, handler_monitor: nil, current_job: nil})
      end
    else
      do_handle_sdk_error(reason, state)
    end
  end

  # SDK error
  @impl true
  def handle_info({:claude_error, ref, reason}, %__MODULE__{sdk_ref: ref} = state) do
    WorkerEvents.broadcast_stream_clear(state.session_id)
    do_handle_sdk_error(reason, %{state | stream: StreamAssembler.reset(state.stream)})
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
    Logger.error(
      "[#{state.session_id}] SDK handler crashed: #{inspect(reason)}"
    )

    WorkerEvents.broadcast_stream_clear(state.session_id)

    do_handle_sdk_error(
      {:handler_crash, reason},
      %{state | stream: StreamAssembler.reset(state.stream), handler_monitor: nil}
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
    if state.sdk_ref, do: cancel_sdk(state.provider || "claude", state.sdk_ref)
    :ok
  end

  # --- Private ---

  defp broadcast_events(events, state) do
    topic = "dm:#{state.session_id}:stream"

    Enum.each(events, fn event ->
      Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, topic, event)
    end)
  end


  defp process_next_job(%__MODULE__{queue: []} = state) do
    WorkerEvents.broadcast_queue_update(state.session_id, state.queue)
    {:noreply, state}
  end

  defp process_next_job(%__MODULE__{queue: [next_job | rest]} = state) do
    case start_sdk(state, next_job) do
      {:ok, sdk_ref, handler_monitor} ->
        WorkerEvents.on_sdk_started(state.session_id, state.provider_conversation_id)

        new_state =
          clear_retry_timer(%{state | status: :running, sdk_ref: sdk_ref, handler_monitor: handler_monitor, current_job: next_job, queue: rest})

        WorkerEvents.broadcast_queue_update(state.session_id, new_state.queue)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to start SDK for next job: #{inspect(reason)}")
        {:noreply, %{state | queue: [next_job | rest]} |> schedule_retry_start()}
    end
  end

  defp start_sdk(%__MODULE__{provider: "codex"} = state, job) do
    monitor_handler(start_codex_sdk(state, job))
  end

  defp start_sdk(state, job) do
    monitor_handler(start_claude_sdk(state, job))
  end

  # Convert {:ok, sdk_ref, handler_pid} to {:ok, sdk_ref, monitor_ref}
  defp monitor_handler({:ok, sdk_ref, handler_pid}) do
    monitor_ref = Process.monitor(handler_pid)
    {:ok, sdk_ref, monitor_ref}
  end

  defp monitor_handler({:error, _} = error), do: error

  defp start_claude_sdk(state, job) do
    context = job.context
    has_messages = context[:has_messages] || false
    prompt = job.message

    opts = [
      to: self(),
      model: context[:model],
      session_id: state.provider_conversation_id,
      project_path: state.project_path,
      skip_permissions: true,
      use_script: true,
      eits_session_id: state.provider_conversation_id,
      eits_agent_id: state.agent_id,
      eits_workflow: context[:eits_workflow] || "1",
      worktree: state.worktree,
      agent: context[:agent]
    ]

    opts =
      if context[:effort_level] && context[:effort_level] != "" do
        opts ++ [effort_level: context[:effort_level]]
      else
        opts
      end

    opts =
      if context[:thinking_budget] do
        opts ++ [thinking_budget: context[:thinking_budget]]
      else
        opts
      end

    opts =
      if context[:max_budget_usd] do
        opts ++ [max_budget_usd: context[:max_budget_usd]]
      else
        opts
      end

    if has_messages do
      Logger.info("Resuming Claude session #{state.provider_conversation_id}")
      SDK.resume(state.provider_conversation_id, prompt, opts)
    else
      Logger.info("Starting new Claude session #{state.provider_conversation_id}")
      SDK.start(prompt, opts)
    end
  end

  defp start_codex_sdk(state, job) do
    context = job.context
    has_messages = context[:has_messages] || false
    prompt = job.message

    opts = [
      to: self(),
      model: context[:model],
      session_id: state.provider_conversation_id,
      project_path: state.project_path,
      full_auto: true,
      eits_session_id: state.provider_conversation_id,
      eits_agent_id: state.agent_id,
      eits_model: context[:model]
    ]

    if has_messages do
      Logger.info("Resuming Codex session #{state.provider_conversation_id}")
      Codex.SDK.resume(state.provider_conversation_id, prompt, opts)
    else
      Logger.info("Starting new Codex session #{state.provider_conversation_id}")

      full_prompt =
        codex_eits_init(state.provider_conversation_id, context[:model]) <> "\n\n---\n\n" <> prompt

      Codex.SDK.start(full_prompt, opts)
    end
  end

  defp codex_eits_init(provider_conversation_id, model) do
    """
    IMPORTANT: Before doing anything else, complete these EITS registration steps:

    1. Get your Codex session ID by running:
       ~/.claude/eye-in-the-sky/codex-session-find #{provider_conversation_id}

    2. Your EITS session UUID is: #{provider_conversation_id}
       Model: #{model || "unknown"}
       Provider: openai

    3. Follow the EITS workflow for all work:
       a. Create a task:
          i-todo create --title "<task title>" --description "<details>"
       b. Start the task (move to In Progress):
          i-todo start <task_id>
       c. Link task to your session:
          i-todo add-session <task_id> --session_id #{provider_conversation_id}
       d. Do the work.
       e. When done, move task to In Review (NOT Done):
          i-todo status <task_id> --state_id 4

    4. When all work is complete, end the session:
       i-session end #{provider_conversation_id}

    Now proceed with the task:
    """
  end

  defp cancel_sdk("codex", ref), do: Codex.SDK.cancel(ref)
  defp cancel_sdk(_provider, ref), do: SDK.cancel(ref)

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

    %{state | status: :failed, queue: [], retry_attempt: 0}
  end

  defp schedule_retry_start(%__MODULE__{retry_timer_ref: nil} = state) do
    delay = min(round(@retry_start_ms * :math.pow(2, state.retry_attempt)), @retry_max_ms)

    Logger.info(
      "[#{state.session_id}] Scheduling retry in #{delay}ms (attempt=#{state.retry_attempt})"
    )

    timer_ref = Process.send_after(self(), :retry_start, delay)
    %{state | status: :retry_wait, retry_timer_ref: timer_ref, retry_attempt: state.retry_attempt + 1}
  end

  defp schedule_retry_start(state), do: state

  defp clear_retry_timer(%__MODULE__{retry_timer_ref: nil} = state), do: %{state | retry_attempt: 0}

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
      eits_workflow: Map.get(context, :eits_workflow, "1")
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
      eits_workflow: context[:eits_workflow] || "1"
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
      eits_workflow: "1"
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

    Logger.error(
      "[telemetry] agent.sdk.error session_id=#{state.session_id} reason=#{inspect(reason)}"
    )

    WorkerEvents.on_sdk_errored(state.session_id, state.provider_conversation_id)
    demonitor_handler(state.handler_monitor)

    if systemic_error?(reason) do
      WorkerEvents.on_queue_drained(
        state.session_id,
        state.provider_conversation_id,
        state.queue,
        reason
      )

      {:noreply, %{state | status: :failed, sdk_ref: nil, handler_monitor: nil, current_job: nil, queue: []}}
    else
      process_next_job(%{state | status: :idle, sdk_ref: nil, handler_monitor: nil, current_job: nil})
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
