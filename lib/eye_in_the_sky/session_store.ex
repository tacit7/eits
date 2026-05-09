defmodule EyeInTheSky.SessionStore do
  @moduledoc """
  ETS-backed in-memory session store with TTL-based expiration.

  Stores session data in an ETS table and periodically cleans up expired entries
  based on configurable TTL. Prevents unbounded ETS growth by removing entries
  older than the specified time-to-live duration.

  ## Entry Format

  Each entry is stored as a tuple: `{session_id, data, inserted_at_ms}` where:
  - `session_id`: unique session identifier
  - `data`: the session data (any term)
  - `inserted_at_ms`: system timestamp in milliseconds when entry was created/updated

  ## Configuration

  The module uses module attributes for configuration:
  - `@table`: ETS table name (default: `:session_store`)
  - `@default_ttl_ms`: default TTL in milliseconds (default: 3600000 = 1 hour)
  - `@cleanup_interval_ms`: how often to run cleanup (default: 1800000 = 30 minutes)
  """

  use GenServer
  require Logger

  # ETS table name
  @table :session_store

  # Default TTL: 1 hour in milliseconds
  @default_ttl_ms 1 * 60 * 60 * 1000

  # Cleanup interval: 30 minutes in milliseconds
  @cleanup_interval_ms 30 * 60 * 1000

  # ── Public API ─────────────────────────────────────────────────────────────

  @doc """
  Starts the SessionStore GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Saves or updates session data in the store.

  Updates the insertion timestamp to the current time, effectively resetting TTL.

  ## Examples

      iex> EyeInTheSky.SessionStore.save("session_123", %{user_id: 1})
      :ok
  """
  @spec save(term(), term()) :: :ok
  def save(session_id, data) do
    :ets.insert(@table, {session_id, data, System.system_time(:millisecond)})
    :ok
  end

  @doc """
  Loads session data from the store.

  Returns `{:ok, data}` if the session exists, or `{:error, :not_found}` otherwise.

  ## Examples

      iex> EyeInTheSky.SessionStore.load("session_123")
      {:ok, %{user_id: 1}}

      iex> EyeInTheSky.SessionStore.load("nonexistent")
      {:error, :not_found}
  """
  @spec load(term()) :: {:ok, term()} | {:error, :not_found}
  def load(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, data, _ts}] -> {:ok, data}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Deletes a session from the store.

  Returns `:ok` whether or not the session exists.

  ## Examples

      iex> EyeInTheSky.SessionStore.delete("session_123")
      :ok
  """
  @spec delete(term()) :: :ok
  def delete(session_id) do
    :ets.delete(@table, session_id)
    :ok
  end

  @doc """
  Updates the TTL of an existing session by refreshing its timestamp.

  If the session doesn't exist, returns `{:error, :not_found}`.
  Otherwise, updates the insertion timestamp to the current time, giving the
  entry a fresh TTL window.

  ## Examples

      iex> EyeInTheSky.SessionStore.update_ttl("session_123")
      :ok

      iex> EyeInTheSky.SessionStore.update_ttl("nonexistent")
      {:error, :not_found}
  """
  @spec update_ttl(term()) :: :ok | {:error, :not_found}
  def update_ttl(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, data, _old_ts}] ->
        :ets.insert(@table, {session_id, data, System.system_time(:millisecond)})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active (non-expired) session IDs in the store.

  Uses the default TTL to determine which sessions are still valid.

  ## Examples

      iex> EyeInTheSky.SessionStore.list_active()
      ["session_123", "session_456"]
  """
  @spec list_active() :: [term()]
  def list_active do
    now = System.system_time(:millisecond)
    cutoff = now - @default_ttl_ms

    :ets.select(@table, [
      {{:"$1", :_, :"$2"}, [{:>, :"$2", cutoff}], [:"$1"]}
    ])
  end

  @doc """
  Returns the number of sessions currently in the store.

  ## Examples

      iex> EyeInTheSky.SessionStore.count()
      42
  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@table, :size)
  end

  # ── GenServer Callbacks ────────────────────────────────────────────────────

  @impl GenServer
  def init(_opts) do
    # Create the ETS table if it doesn't exist
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _tid ->
        # Table already exists, just use it
        :ok
    end

    # Schedule the cleanup timer
    schedule_cleanup()
    Logger.info("SessionStore started with TTL=#{@default_ttl_ms}ms, cleanup interval=#{@cleanup_interval_ms}ms")

    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:cleanup_expired, state) do
    now = System.system_time(:millisecond)
    cutoff = now - @default_ttl_ms

    # Delete all entries with timestamp older than cutoff
    deleted = :ets.select_delete(@table, [
      {{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}
    ])

    if deleted > 0 do
      Logger.debug("SessionStore cleanup: deleted #{deleted} expired sessions")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  # ── Private Helpers ────────────────────────────────────────────────────────

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
  end
end
