defmodule EyeInTheSky.Gemini.StreamHandler.Registry do
  @moduledoc """
  ETS-backed registry for Gemini stream tasks.

  Entries are keyed by `sdk_ref` and monitor the registered pid. When the
  pid terminates (normal completion, error, crash, or cancel), the entry
  is removed automatically so no stale refs accumulate.
  """
  use GenServer

  @table :eits_gemini_stream_registry

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :protected, :set])
    # Secondary index: monitor_ref -> sdk_ref, so :DOWN can find the entry.
    :ets.new(monitor_table(), [:named_table, :protected, :set])
    {:ok, %{}}
  end

  def register(ref, pid) do
    GenServer.call(__MODULE__, {:register, ref, pid})
  end

  def lookup(ref) do
    case :ets.lookup(@table, ref) do
      [{^ref, pid, _mon}] -> pid
      [] -> nil
    end
  end

  def unregister(ref) do
    GenServer.call(__MODULE__, {:unregister, ref})
  end

  @impl true
  def handle_call({:register, ref, pid}, _from, state) do
    mon = Process.monitor(pid)
    :ets.insert(@table, {ref, pid, mon})
    :ets.insert(monitor_table(), {mon, ref})
    {:reply, :ok, state}
  end

  def handle_call({:unregister, ref}, _from, state) do
    case :ets.lookup(@table, ref) do
      [{^ref, _pid, mon}] ->
        Process.demonitor(mon, [:flush])
        :ets.delete(@table, ref)
        :ets.delete(monitor_table(), mon)

      [] ->
        :ok
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, mon, :process, _pid, _reason}, state) do
    case :ets.lookup(monitor_table(), mon) do
      [{^mon, ref}] ->
        :ets.delete(@table, ref)
        :ets.delete(monitor_table(), mon)

      [] ->
        :ok
    end

    {:noreply, state}
  end

  defp monitor_table, do: :eits_gemini_stream_registry_monitors
end
