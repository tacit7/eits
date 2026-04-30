defmodule EyeInTheSky.Claude.AgentWorker.Reconciliation do
  @moduledoc """
  Side-effect and reconciliation functions extracted from AgentWorker.

  Handles provider conversation ID syncing, session failure marking,
  command dispatching, stream event broadcasting, trace lifecycle,
  and telemetry emission.
  """

  require Logger

  alias EyeInTheSky.AgentWorkerEvents, as: WorkerEvents
  alias EyeInTheSky.Agents.CmdDispatcher
  alias EyeInTheSky.Claude.Message
  alias EyeInTheSky.Messages.Trace

  @doc """
  Strips EITS-CMD directives from text messages and dispatches them.
  Returns the message unchanged for non-text messages.
  """
  def maybe_dispatch_commands(%Message{type: :text, content: content} = msg, state)
      when is_binary(content) do
    case CmdDispatcher.extract_commands(content) do
      {[], _} ->
        msg

      {cmds, clean} ->
        CmdDispatcher.dispatch_all(cmds, state.session_id)
        %{msg | content: clean}
    end
  end

  def maybe_dispatch_commands(msg, _state), do: msg

  @doc """
  Updates provider_conversation_id when the provider returns a new one.
  No-ops if the ID is unchanged or empty.
  """
  def maybe_sync_provider_conversation_id(state, provider_id)
      when is_binary(provider_id) and provider_id != "" do
    if state.provider_conversation_id == provider_id do
      state
    else
      WorkerEvents.on_provider_conversation_id_changed(
        state.session_id,
        state.provider_conversation_id,
        provider_id
      )

      %{state | provider_conversation_id: provider_id}
    end
  end

  def maybe_sync_provider_conversation_id(state, _), do: state

  @doc """
  Marks the session as failed on abnormal GenServer termination.
  Normal exits (:normal, :shutdown, {:shutdown, _}) are no-ops.
  """
  def maybe_mark_session_failed(:normal, _state), do: :ok
  def maybe_mark_session_failed(:shutdown, _state), do: :ok
  def maybe_mark_session_failed({:shutdown, _}, _state), do: :ok

  def maybe_mark_session_failed(reason, %{
        session_id: session_id,
        provider_conversation_id: pcid
      }) do
    Logger.warning(
      "AgentWorker terminating abnormally for session_id=#{session_id}: #{inspect(reason)}"
    )

    try do
      EyeInTheSky.AgentWorkerEvents.on_session_failed(session_id, pcid, reason)
    rescue
      e ->
        Logger.error("Failed to mark session failed on abnormal terminate: #{inspect(e)}")
    end
  end

  @doc """
  Broadcasts stream events asynchronously via TaskSupervisor to avoid blocking the GenServer.
  """
  def broadcast_events(events, state) do
    meta = Logger.metadata()

    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      Logger.metadata(meta)

      Enum.each(events, fn event ->
        EyeInTheSky.Events.stream_event(state.session_id, event)
      end)
    end)
  end

  @doc """
  Starts a new message trace and records the trace ID in Logger metadata.
  """
  def start_job_trace(state) do
    trace_id = Trace.new()
    Trace.set_in_logger(trace_id)
    %{state | message_trace_id: trace_id}
  end

  @doc """
  Clears the current message trace from state and Logger metadata.
  """
  def clear_job_trace(state) do
    Logger.metadata(message_trace_id: nil)
    %{state | message_trace_id: nil}
  end

  @doc """
  Executes a telemetry event with session and trace metadata attached.
  """
  def emit(event, measurements, state) do
    emit(event, measurements, %{}, state)
  end

  def emit(event, measurements, extra_meta, state) do
    meta =
      extra_meta
      |> Map.put(:session_id, state.session_id)
      |> Map.put(:message_trace_id, state.message_trace_id)

    :telemetry.execute(event, measurements, meta)
  end
end
