defmodule EyeInTheSkyWeb.MCP.SessionStore do
  @moduledoc """
  ETS-backed session store for the Anubis MCP server.

  Persists session state within the Phoenix process lifetime so that when
  a session Agent is restarted (crash, cleanup, reconnect), it can restore
  its `initialized: true` state and avoid the "Server not initialized" warning.
  """

  @behaviour Anubis.Server.Session.Store

  use GenServer

  @table :mcp_sessions

  # ── Anubis.Server.Session.Store callbacks ──────────────────────────────────

  @impl Anubis.Server.Session.Store
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Anubis.Server.Session.Store
  def save(session_id, state, _opts) do
    # Strip the GenServer name — it's process-specific and changes on restart.
    storable = Map.put(state, :name, nil)
    :ets.insert(@table, {session_id, storable, System.system_time(:millisecond)})
    :ok
  end

  @impl Anubis.Server.Session.Store
  def load(session_id, _opts) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, state, _ts}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end

  @impl Anubis.Server.Session.Store
  def delete(session_id, _opts) do
    :ets.delete(@table, session_id)
    :ok
  end

  @impl Anubis.Server.Session.Store
  def list_active(_opts) do
    ids = :ets.select(@table, [{{:"$1", :_, :_}, [], [:"$1"]}])
    {:ok, ids}
  end

  @impl Anubis.Server.Session.Store
  def update_ttl(_session_id, _ttl_ms, _opts) do
    # ETS has no native TTL; no-op.
    :ok
  end

  @impl Anubis.Server.Session.Store
  def update(session_id, updates, _opts) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, state, ts}] ->
        :ets.insert(@table, {session_id, Map.merge(state, updates), ts})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  # ── GenServer ──────────────────────────────────────────────────────────────

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end
end
