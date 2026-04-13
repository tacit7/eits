defmodule EyeInTheSky.OrchestratorTimers.Server do
  @moduledoc """
  In-memory timer registry for orchestrator sessions.

  Manages one active timer per session. Timers outlive the DM page LiveView
  socket because this GenServer runs under the application supervisor.

  Each timer carries a unique token (make_ref/0). When Process.cancel_timer/1
  is called, the old message may already be in the mailbox — the token prevents
  stale messages from firing.
  """

  use GenServer
  require Logger

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Events
  alias EyeInTheSky.OrchestratorTimers.Timer

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:schedule_once, session_id, delay_ms, message}, _from, state) do
    {result, new_state} = build_and_store_timer(session_id, :once, delay_ms, message, state)
    {:reply, result, new_state}
  end

  @impl GenServer
  def handle_call({:schedule_repeating, session_id, interval_ms, message}, _from, state) do
    {result, new_state} = build_and_store_timer(session_id, :repeating, interval_ms, message, state)
    {:reply, result, new_state}
  end

  @impl GenServer
  def handle_call({:cancel, session_id}, _from, state) do
    case Map.get(state, session_id) do
      nil ->
        {:reply, {:ok, :noop}, state}

      _ ->
        new_state = cancel_existing(state, session_id)
        Logger.info("[OrchestratorTimers] cancelled session=#{session_id}")
        Events.timer_cancelled(session_id)
        {:reply, {:ok, :cancelled}, new_state}
    end
  end

  @impl GenServer
  def handle_call({:get_timer, session_id}, _from, state) do
    {:reply, Map.get(state, session_id), state}
  end

  @impl GenServer
  def handle_call(:list_active, _from, state) do
    {:reply, Map.values(state), state}
  end

  @impl GenServer
  def handle_info({:fire_timer, session_id, token}, state) do
    case Map.get(state, session_id) do
      %Timer{token: ^token} = record ->
        do_fire(session_id, record, state)

      nil ->
        # Timer was cancelled and state already cleaned up.
        {:noreply, state}

      _ ->
        # Stale token from a replaced or cancelled timer. Ignore.
        Logger.debug("[OrchestratorTimers] stale timer for session=#{session_id}, ignoring")
        {:noreply, state}
    end
  end

  @min_interval_ms 100

  defp build_and_store_timer(_session_id, _mode, interval_ms, _message, state)
       when interval_ms < @min_interval_ms do
    {{:error, {:invalid_interval, "interval_ms must be >= #{@min_interval_ms}, got #{interval_ms}"}}, state}
  end

  defp build_and_store_timer(session_id, mode, interval_ms, message, state) do
    result = if Map.has_key?(state, session_id), do: {:ok, :replaced}, else: {:ok, :scheduled}
    state = cancel_existing(state, session_id)

    token = make_ref()
    timer_ref = Process.send_after(self(), {:fire_timer, session_id, token}, interval_ms)
    now = DateTime.utc_now()

    record = %Timer{
      token: token,
      timer_ref: timer_ref,
      mode: mode,
      interval_ms: interval_ms,
      message: message,
      started_at: now,
      next_fire_at: DateTime.add(now, interval_ms, :millisecond)
    }

    label = if result == {:ok, :replaced}, do: "replaced", else: "scheduled"
    Logger.info("[OrchestratorTimers] #{label} #{mode} session=#{session_id} interval_ms=#{interval_ms} next_fire_at=#{record.next_fire_at}")

    Events.timer_scheduled(session_id, record)
    {result, Map.put(state, session_id, record)}
  end

  defp do_fire(session_id, %Timer{} = record, state) do
    Logger.info("[OrchestratorTimers] timer fired session=#{session_id} mode=#{record.mode}")

    case AgentManager.send_message(session_id, record.message, []) do
      {:ok, _} ->
        Logger.debug("[OrchestratorTimers] delivery succeeded session=#{session_id}")

      {:error, reason} ->
        Logger.warning("[OrchestratorTimers] delivery failed session=#{session_id} reason=#{inspect(reason)}")
    end

    case record.mode do
      :once ->
        Events.timer_fired(session_id, nil)
        {:noreply, Map.delete(state, session_id)}

      :repeating ->
        token = make_ref()
        timer_ref = Process.send_after(self(), {:fire_timer, session_id, token}, record.interval_ms)
        now = DateTime.utc_now()

        new_record = %Timer{
          record
          | token: token,
            timer_ref: timer_ref,
            next_fire_at: DateTime.add(now, record.interval_ms, :millisecond)
        }

        Events.timer_fired(session_id, new_record)
        {:noreply, Map.put(state, session_id, new_record)}
    end
  end

  defp cancel_existing(state, session_id) do
    case Map.get(state, session_id) do
      nil ->
        state

      %Timer{timer_ref: ref} ->
        Process.cancel_timer(ref)
        Map.delete(state, session_id)
    end
  end
end
