defmodule EyeInTheSky.PendingSessionMessages do
  @moduledoc "Short-lived one-shot store for initial DM bodies + send opts. Consumed on first read."
  use GenServer

  @table :pending_session_messages
  @ttl_ms 60_000
  @sweep_interval_ms 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end

  @doc "Store body + send_opts for session_id. Overwrites any existing entry. TTL: 60s."
  def put(session_id, body, send_opts \\ [])
      when is_integer(session_id) and is_binary(body) and is_list(send_opts) do
    expires = System.monotonic_time(:millisecond) + @ttl_ms
    :ets.insert(@table, {session_id, {body, send_opts}, expires})
    :ok
  end

  @doc "Atomically retrieve and delete. Returns {body, send_opts} or nil if absent/expired."
  def pop(session_id) when is_integer(session_id) do
    case :ets.take(@table, session_id) do
      [{^session_id, {body, send_opts}, expires}] ->
        if System.monotonic_time(:millisecond) <= expires, do: {body, send_opts}, else: nil

      [] ->
        nil
    end
  end
end
