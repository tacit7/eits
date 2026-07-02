defmodule EyeInTheSky.Claude.SDK.Registry do
  @moduledoc false
  use GenServer

  @table __MODULE__

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, nil}
  end

  def register(ref, port) do
    :ets.insert(@table, {ref, port})
    :ok
  end

  def lookup(ref) do
    case :ets.lookup(@table, ref) do
      [{^ref, port}] -> port
      [] -> nil
    end
  end

  def unregister(ref) do
    :ets.delete(@table, ref)
    :ok
  end
end
