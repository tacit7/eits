defmodule EyeInTheSkyWeb.Claude.AgentWorker do
  @moduledoc """
  Persistent per-agent GenServer managing message queue and Claude lifecycle.

  One AgentWorker per session (agent). Uses the Claude SDK for streaming and
  manages a queue of pending messages. When busy, queues new messages.
  When Claude completes, processes the next queued message automatically.
  """

  use GenServer
  require Logger

  alias EyeInTheSkyWeb.Claude.{Message, SDK}
  alias EyeInTheSkyWeb.Codex
  alias EyeInTheSkyWeb.{Messages, Sessions}

  @registry EyeInTheSkyWeb.Claude.AgentRegistry
  @retry_start_ms 1_000

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

  def cancel(session_id) do
    case Registry.lookup(@registry, {:agent, session_id}) do
      [{pid, _}] -> GenServer.cast(pid, :cancel)
      [] -> {:error, :not_found}
    end
  end

  def is_processing?(session_id) do
    case Registry.lookup(@registry, {:agent, session_id}) do
      [{pid, _}] -> GenServer.call(pid, :is_processing?)
      [] -> false
    end
  end

  def get_queue(session_id) do
    case Registry.lookup(@registry, {:agent, session_id}) do
      [{pid, _}] -> GenServer.call(pid, :get_queue)
      [] -> []
    end
  end

  def get_stream_state(session_id) do
    case Registry.lookup(@registry, {:agent, session_id}) do
      [{pid, _}] -> GenServer.call(pid, :get_stream_state)
      [] -> ""
    end
  end

  def remove_queued_prompt(session_id, prompt_id) do
    case Registry.lookup(@registry, {:agent, session_id}) do
      [{pid, _}] -> GenServer.cast(pid, {:remove_queued_prompt, prompt_id})
      [] -> :ok
    end
  end

  # --- Server Callbacks ---

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    session_uuid = Keyword.fetch!(opts, :session_uuid)
    agent_id = Keyword.fetch!(opts, :agent_id)
    project_path = Keyword.get(opts, :project_path, File.cwd!())
    provider = Keyword.get(opts, :provider, "claude")
    worktree = Keyword.get(opts, :worktree)

    state = %{
      session_id: session_id,
      session_uuid: session_uuid,
      agent_id: agent_id,
      sdk_ref: nil,
      current_job: nil,
      queue: [],
      project_path: project_path,
      provider: provider,
      worktree: worktree,
      retry_timer_ref: nil,
      stream_buffer: "",
      current_tool_id: nil,
      current_tool_name: nil,
      current_tool_input: ""
    }

    Logger.info(
      "AgentWorker started for session=#{session_id} agent=#{agent_id} provider=#{provider}"
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:is_processing?, _from, state) do
    {:reply, not is_nil(state.current_job), state}
  end

  @impl true
  def handle_call(:get_queue, _from, state) do
    {:reply, state.queue, state}
  end

  @impl true
  def handle_call(:get_stream_state, _from, state) do
    {:reply, state.stream_buffer, state}
  end

  @impl true
  def handle_cast({:process_message, message, context}, state) when is_binary(message) do
    context = normalize_context(context)

    Logger.info(
      "AgentWorker.process_message: session_id=#{state.session_id}, " <>
        "message_length=#{String.length(message)}, has_messages=#{context.has_messages}, " <>
        "model=#{inspect(context.model)}"
    )

    queue_len = length(state.queue)
    has_msgs = context.has_messages

    :telemetry.execute([:eits, :agent, :job, :received], %{system_time: System.system_time()}, %{
      session_id: state.session_id,
      queue_length: queue_len,
      has_messages: has_msgs
    })

    Logger.info(
      "[telemetry] agent.job.received session_id=#{state.session_id} queue=#{queue_len} has_messages=#{has_msgs}"
    )

    job = %{
      message: message,
      context: context,
      queued_at: DateTime.utc_now()
    }

    if state.sdk_ref == nil do
      # Idle, start SDK immediately
      Logger.info("AgentWorker: starting SDK for session_id=#{state.session_id}")

      case start_sdk(state, job) do
        {:ok, sdk_ref} ->
          Logger.info("AgentWorker: SDK started for session_id=#{state.session_id}")

          :telemetry.execute(
            [:eits, :agent, :job, :started],
            %{system_time: System.system_time()},
            %{
              session_id: state.session_id
            }
          )

          Logger.info("[telemetry] agent.job.started session_id=#{state.session_id}")

          update_agent_status(state.session_id, "working")

          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "agent:working",
            {:agent_working, state.session_uuid, state.session_id}
          )

          {:noreply, clear_retry_timer(%{state | sdk_ref: sdk_ref, current_job: job})}

        {:error, reason} ->
          Logger.error(
            "AgentWorker: failed to start SDK for session_id=#{state.session_id} - #{inspect(reason)}"
          )

          {:noreply, state |> enqueue_job(job) |> schedule_retry_start()}
      end
    else
      # Busy, queue the job
      new_queue_length = length(state.queue) + 1

      Logger.info(
        "AgentWorker: busy, queueing message for session_id=#{state.session_id}, " <>
          "queue_length=#{new_queue_length}"
      )

      :telemetry.execute([:eits, :agent, :job, :queued], %{queue_length: new_queue_length}, %{
        session_id: state.session_id
      })

      Logger.info(
        "[telemetry] agent.job.queued session_id=#{state.session_id} queue_length=#{new_queue_length}"
      )

      {:noreply, enqueue_job(state, job)}
    end
  end

  def handle_cast({:process_message, message, _context}, state) do
    Logger.warning(
      "AgentWorker.process_message: invalid message payload for session_id=#{state.session_id} message=#{inspect(message)}"
    )

    {:noreply, state}
  end

  @impl true
  def handle_cast(:cancel, %{sdk_ref: nil} = state) do
    {:noreply, state}
  end

  def handle_cast(:cancel, %{sdk_ref: ref} = state) do
    Logger.info("[#{state.session_id}] Cancelling SDK process (provider=#{state.provider})")
    cancel_sdk(state.provider, ref)
    {:noreply, state}
  end

  def handle_cast({:remove_queued_prompt, prompt_id}, state) do
    new_queue = Enum.reject(state.queue, fn job -> job[:id] == prompt_id end)
    new_state = %{state | queue: new_queue}
    broadcast_queue_update(new_state)
    {:noreply, new_state}
  end

  # SDK result message - contains the final response text + metadata for DB storage
  @impl true
  def handle_info(
        {:claude_message, ref, %Message{type: :result, content: text, metadata: metadata}},
        %{sdk_ref: ref} = state
      ) do
    state = maybe_sync_session_uuid(state, metadata[:session_id])
    save_result(text, metadata, state)

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
        %{sdk_ref: ref} = state
      )
      when is_binary(json) do
    state = %{state | current_tool_input: state.current_tool_input <> json}
    {:noreply, state}
  end

  # Other SDK messages (text deltas, tool use, thinking, etc.) - broadcast for live streaming
  @impl true
  def handle_info({:claude_message, ref, %Message{} = msg}, %{sdk_ref: ref} = state) do
    state = update_tool_start(msg, state)
    broadcast_stream_event(msg, state)
    state = update_stream_buffer(msg, state)
    {:noreply, state}
  end

  # Tool block complete - decode accumulated input and broadcast
  @impl true
  def handle_info({:tool_block_stop, ref}, %{sdk_ref: ref} = state) do
    state =
      if state.current_tool_id do
        input =
          case Jason.decode(state.current_tool_input) do
            {:ok, decoded} -> decoded
            {:error, _} -> %{raw: state.current_tool_input}
          end

        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "dm:#{state.session_id}:stream",
          {:stream_tool_input, state.current_tool_name, input}
        )

        %{state | current_tool_id: nil, current_tool_name: nil, current_tool_input: ""}
      else
        state
      end

    {:noreply, state}
  end

  # Stale tool_block_stop from old sdk ref - ignore
  @impl true
  def handle_info({:tool_block_stop, _ref}, state), do: {:noreply, state}

  # SDK completion - process next queued job
  @impl true
  def handle_info({:claude_complete, ref, session_id}, %{sdk_ref: ref} = state) do
    state = maybe_sync_session_uuid(state, session_id)
    broadcast_stream_clear(state)
    state = %{state | stream_buffer: "", current_tool_id: nil, current_tool_name: nil, current_tool_input: ""}

    Logger.info("[#{state.session_id}] SDK complete")

    :telemetry.execute([:eits, :agent, :sdk, :complete], %{system_time: System.system_time()}, %{
      session_id: state.session_id
    })

    Logger.info("[telemetry] agent.sdk.complete session_id=#{state.session_id}")

    update_agent_status(state.session_id, "idle")

    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "agent:working",
      {:agent_stopped, state.session_uuid, state.session_id}
    )

    notify_agent_complete(state)

    process_next_job(%{state | sdk_ref: nil, current_job: nil})
  end

  # Stale Claude session — retry current job as a fresh start
  @impl true
  def handle_info(
        {:claude_error, ref, {:claude_result_error, %{errors: errors}} = reason},
        %{sdk_ref: ref, current_job: job} = state
      )
      when is_list(errors) do
    broadcast_stream_clear(state)
    state = %{state | stream_buffer: "", current_tool_id: nil, current_tool_name: nil, current_tool_input: ""}

    if Enum.any?(errors, &String.contains?(&1, "No conversation found")) && not is_nil(job) do
      Logger.warning(
        "[#{state.session_id}] Stale Claude session UUID=#{state.session_uuid}, retrying as new session"
      )

      fresh_job = put_in(job, [:context, :has_messages], false)

      case start_sdk(state, fresh_job) do
        {:ok, sdk_ref} ->
          {:noreply, %{state | sdk_ref: sdk_ref, current_job: fresh_job}}

        {:error, start_reason} ->
          Logger.error(
            "[#{state.session_id}] Failed to restart fresh SDK: #{inspect(start_reason)}"
          )

          update_agent_status(state.session_id, "idle")

          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "agent:working",
            {:agent_stopped, state.session_uuid, state.session_id}
          )

          process_next_job(%{state | sdk_ref: nil, current_job: nil})
      end
    else
      do_handle_sdk_error(reason, state)
    end
  end

  # SDK error
  @impl true
  def handle_info({:claude_error, ref, reason}, %{sdk_ref: ref} = state) do
    broadcast_stream_clear(state)
    do_handle_sdk_error(reason, %{state | stream_buffer: "", current_tool_id: nil, current_tool_name: nil, current_tool_input: ""})
  end

  # Stale messages from previous SDK refs - ignore
  @impl true
  def handle_info({:claude_message, _ref, _msg}, state), do: {:noreply, state}

  @impl true
  def handle_info({:claude_complete, _ref, _sid}, state), do: {:noreply, state}

  @impl true
  def handle_info({:claude_error, _ref, _reason}, state), do: {:noreply, state}

  @impl true
  def handle_info(:retry_start, %{sdk_ref: nil, queue: [_ | _]} = state) do
    process_next_job(%{state | retry_timer_ref: nil})
  end

  @impl true
  def handle_info(:retry_start, state) do
    {:noreply, %{state | retry_timer_ref: nil}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message in AgentWorker: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state[:sdk_ref], do: cancel_sdk(state[:provider] || "claude", state.sdk_ref)
    :ok
  end

  # --- Private ---

  defp save_result(text, metadata, state) when is_binary(text) do
    if String.trim(text) in ["", "[NO_RESPONSE]"] do
      Logger.info("[#{state.session_id}] Skipping DB save — empty or suppressed response")
    else
      channel_id = get_in(state, [:current_job, :context, :channel_id])

      db_metadata = %{
        duration_ms: metadata[:duration_ms],
        total_cost_usd: metadata[:total_cost_usd],
        usage: metadata[:usage],
        model_usage: metadata[:model_usage],
        num_turns: metadata[:num_turns],
        is_error: metadata[:is_error]
      }

      opts = [
        metadata: db_metadata
      ]

      opts = if channel_id, do: Keyword.put(opts, :channel_id, channel_id), else: opts

      case Messages.record_incoming_reply(state.session_id, state.provider, text, opts) do
        {:ok, _message} ->
          :ok

        {:error, reason} ->
          Logger.warning("[#{state.session_id}] DB save failed: #{inspect(reason)}")
      end
    end
  end

  defp save_result(_text, _metadata, state) do
    Logger.warning("[#{state.session_id}] Result has no text content")
  end

  defp process_next_job(%{queue: []} = state) do
    broadcast_queue_update(state)
    {:noreply, state}
  end

  defp process_next_job(%{queue: [next_job | rest]} = state) do
    case start_sdk(state, next_job) do
      {:ok, sdk_ref} ->
        update_agent_status(state.session_id, "working")

        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "agent:working",
          {:agent_working, state.session_uuid, state.session_id}
        )

        new_state =
          clear_retry_timer(%{state | sdk_ref: sdk_ref, current_job: next_job, queue: rest})

        broadcast_queue_update(new_state)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to start SDK for next job: #{inspect(reason)}")
        {:noreply, %{state | queue: [next_job | rest]} |> schedule_retry_start()}
    end
  end

  defp start_sdk(%{provider: "codex"} = state, job) do
    start_codex_sdk(state, job)
  end

  defp start_sdk(state, job) do
    start_claude_sdk(state, job)
  end

  defp start_claude_sdk(state, job) do
    context = job.context
    has_messages = context[:has_messages] || false
    prompt = job.message

    opts = [
      to: self(),
      model: context[:model],
      session_id: state.session_uuid,
      project_path: state.project_path,
      skip_permissions: true,
      use_script: true,
      eits_session_id: state.session_uuid,
      eits_agent_id: state.agent_id,
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

    if has_messages do
      Logger.info("Resuming Claude session #{state.session_uuid}")
      SDK.resume(state.session_uuid, prompt, opts)
    else
      Logger.info("Starting new Claude session #{state.session_uuid}")
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
      session_id: state.session_uuid,
      project_path: state.project_path,
      full_auto: true,
      eits_session_id: state.session_uuid,
      eits_agent_id: state.agent_id,
      eits_model: context[:model]
    ]

    if has_messages do
      Logger.info("Resuming Codex session #{state.session_uuid}")
      Codex.SDK.resume(state.session_uuid, prompt, opts)
    else
      Logger.info("Starting new Codex session #{state.session_uuid}")

      full_prompt =
        codex_eits_init(state.session_uuid, context[:model]) <> "\n\n---\n\n" <> prompt

      Codex.SDK.start(full_prompt, opts)
    end
  end

  defp codex_eits_init(session_uuid, model) do
    """
    IMPORTANT: Before doing anything else, complete these EITS registration steps:

    1. Get your Codex session ID by running:
       ~/.claude/eye-in-the-sky/codex-session-find #{session_uuid}

    2. Your EITS session UUID is: #{session_uuid}
       Model: #{model || "unknown"}
       Provider: openai

    3. Follow the EITS workflow for all work:
       a. Create a task:
          i-todo create --title "<task title>" --description "<details>"
       b. Start the task (move to In Progress):
          i-todo start <task_id>
       c. Link task to your session:
          i-todo add-session <task_id> --session_id #{session_uuid}
       d. Do the work.
       e. When done, move task to In Review (NOT Done):
          i-todo status <task_id> --state_id 4

    4. When all work is complete, end the session:
       i-session end #{session_uuid}

    Now proceed with the task:
    """
  end

  defp cancel_sdk("codex", ref), do: Codex.SDK.cancel(ref)
  defp cancel_sdk(_provider, ref), do: SDK.cancel(ref)

  defp enqueue_job(state, job) do
    job = Map.put(job, :id, System.unique_integer([:positive, :monotonic]))
    new_state = %{state | queue: state.queue ++ [job]}
    broadcast_queue_update(new_state)
    new_state
  end

  defp schedule_retry_start(%{retry_timer_ref: nil} = state) do
    timer_ref = Process.send_after(self(), :retry_start, @retry_start_ms)
    %{state | retry_timer_ref: timer_ref}
  end

  defp schedule_retry_start(state), do: state

  defp clear_retry_timer(%{retry_timer_ref: nil} = state), do: state

  defp clear_retry_timer(state) do
    Process.cancel_timer(state.retry_timer_ref)
    %{state | retry_timer_ref: nil}
  end

  defp normalize_context(context) when is_map(context) do
    %{
      model: Map.get(context, :model),
      effort_level: Map.get(context, :effort_level),
      has_messages: Map.get(context, :has_messages, false),
      channel_id: Map.get(context, :channel_id),
      thinking_budget: Map.get(context, :thinking_budget),
      agent: Map.get(context, :agent)
    }
  end

  defp normalize_context(context) when is_list(context) do
    %{
      model: context[:model],
      effort_level: context[:effort_level],
      has_messages: context[:has_messages] || false,
      channel_id: context[:channel_id],
      thinking_budget: context[:thinking_budget],
      agent: context[:agent]
    }
  end

  defp normalize_context(_context) do
    %{
      model: nil,
      effort_level: nil,
      has_messages: false,
      channel_id: nil,
      thinking_budget: nil,
      agent: nil
    }
  end

  defp maybe_sync_session_uuid(state, claude_session_uuid)
       when is_binary(claude_session_uuid) and claude_session_uuid != "" do
    if state.session_uuid == claude_session_uuid do
      state
    else
      case Sessions.get_session(state.session_id) do
        {:ok, execution_agent} ->
          case Sessions.update_session(execution_agent, %{uuid: claude_session_uuid}) do
            {:ok, _updated} ->
              Logger.info(
                "[#{state.session_id}] Updated execution session uuid #{state.session_uuid} -> #{claude_session_uuid}"
              )

              %{state | session_uuid: claude_session_uuid}

            {:error, reason} ->
              Logger.warning(
                "[#{state.session_id}] Failed to update execution session uuid: #{inspect(reason)}"
              )

              state
          end

        {:error, reason} ->
          Logger.warning(
            "[#{state.session_id}] Failed to load execution session for uuid sync: #{inspect(reason)}"
          )

          state
      end
    end
  end

  defp maybe_sync_session_uuid(state, _), do: state

  # Text delta (from stream_event with --include-partial-messages)
  defp broadcast_stream_event(%Message{type: :text, content: text, delta: true}, state)
       when is_binary(text) do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "dm:#{state.session_id}:stream",
      {:stream_delta, :text, text}
    )
  end

  # Cumulative assistant text (full replacement, not delta)
  defp broadcast_stream_event(%Message{type: :text, content: text, delta: false}, state)
       when is_binary(text) and text != "" do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "dm:#{state.session_id}:stream",
      {:stream_replace, :text, text}
    )
  end

  # Tool use with name in content map
  defp broadcast_stream_event(%Message{type: :tool_use, content: %{name: name}}, state)
       when is_binary(name) do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "dm:#{state.session_id}:stream",
      {:stream_delta, :tool_use, name}
    )
  end

  # Tool use with name as string content (from content_block_start)
  defp broadcast_stream_event(%Message{type: :tool_use, content: name}, state)
       when is_binary(name) do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "dm:#{state.session_id}:stream",
      {:stream_delta, :tool_use, name}
    )
  end

  defp broadcast_stream_event(%Message{type: :thinking, delta: true}, state) do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "dm:#{state.session_id}:stream",
      {:stream_delta, :thinking, nil}
    )
  end

  # Thinking block (complete, not delta) - from Codex reasoning items
  defp broadcast_stream_event(%Message{type: :thinking, content: text, delta: false}, state)
       when is_binary(text) and text != "" do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "dm:#{state.session_id}:stream",
      {:stream_replace, :thinking, text}
    )
  end

  defp broadcast_stream_event(_msg, _state), do: :ok

  defp broadcast_stream_clear(state) do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "dm:#{state.session_id}:stream",
      :stream_clear
    )
  end

  defp update_stream_buffer(%Message{type: :text, content: text, delta: true}, state)
       when is_binary(text) do
    %{state | stream_buffer: state.stream_buffer <> text}
  end

  defp update_stream_buffer(%Message{type: :text, content: text, delta: false}, state)
       when is_binary(text) do
    %{state | stream_buffer: text}
  end

  defp update_stream_buffer(_msg, state), do: state

  # Track the start of a tool block so we can accumulate its input
  defp update_tool_start(
         %Message{type: :tool_use, delta: false, content: %{name: name}, metadata: %{id: id}},
         state
       ) do
    %{state | current_tool_id: id, current_tool_name: name, current_tool_input: ""}
  end

  defp update_tool_start(_msg, state), do: state

  defp do_handle_sdk_error(reason, state) do
    Logger.error("[#{state.session_id}] SDK error: #{inspect(reason)}")

    :telemetry.execute([:eits, :agent, :sdk, :error], %{system_time: System.system_time()}, %{
      session_id: state.session_id,
      reason: reason
    })

    Logger.error(
      "[telemetry] agent.sdk.error session_id=#{state.session_id} reason=#{inspect(reason)}"
    )

    update_agent_status(state.session_id, "idle")

    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "agent:working",
      {:agent_stopped, state.session_uuid, state.session_id}
    )

    process_next_job(%{state | sdk_ref: nil, current_job: nil})
  end

  defp broadcast_queue_update(state) do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "dm:#{state.session_id}:queue",
      {:queue_updated, state.queue}
    )
  end

  defp update_agent_status(session_id, status) do
    case Sessions.get_session(session_id) do
      {:ok, agent} ->
        attrs = %{status: status}

        attrs =
          if status == "idle" do
            Map.put(attrs, :last_activity_at, DateTime.utc_now() |> DateTime.to_iso8601())
          else
            attrs
          end

        Sessions.update_session(agent, attrs)

      {:error, _} ->
        :ok
    end
  rescue
    e ->
      Logger.warning("[#{session_id}] update_agent_status raised: #{inspect(e)}")
      :ok
  end

  defp notify_agent_complete(state) do
    title =
      case Sessions.get_session(state.session_id) do
        {:ok, session} when is_binary(session.name) and session.name != "" ->
          "Agent finished: #{session.name}"

        _ ->
          "Agent finished"
      end

    EyeInTheSkyWeb.Notifications.notify(title,
      category: :agent,
      resource: {"session", state.session_uuid}
    )
  end
end
