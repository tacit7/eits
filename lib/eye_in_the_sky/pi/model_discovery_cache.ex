defmodule EyeInTheSky.Pi.ModelDiscoveryCache do
  @moduledoc """
  ETS-backed cache of Pi model discovery (spec Phase 2).

  TTL 60_000 ms — past-TTL entries read as :stale but remain served until a
  refresh succeeds (discovery failure must never blank the picker). Invalidate
  on set_api_key / clear_api_key. get_cached/0 NEVER touches the harness.
  """

  use GenServer

  require Logger

  @table :pi_model_discovery
  @ttl_ms 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec get_cached() :: {:ok, [map()], :fresh | :stale} | :empty
  def get_cached do
    case safe_lookup() do
      [{:models, list, expires_at}] ->
        freshness =
          if System.monotonic_time(:millisecond) < expires_at, do: :fresh, else: :stale

        {:ok, list, freshness}

      [] ->
        :empty
    end
  end

  @spec refresh() :: {:ok, [map()]} | {:error, term()}
  # 45_000 must exceed Pi.Control @default_timeout (30_000) + its outer Task.await
  # margin (5_000) so a control timeout surfaces as `{:error, :pi_control_timeout}`
  # from do_refresh/0 rather than as a GenServer.call exit.
  def refresh, do: GenServer.call(__MODULE__, :refresh, 45_000)

  @spec refresh_async() :: :ok
  def refresh_async, do: GenServer.cast(__MODULE__, :refresh)

  @spec invalidate() :: :ok
  def invalidate do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc false
  def __force_expire_for_test__ do
    case safe_lookup() do
      [{:models, list, _}] ->
        past = System.monotonic_time(:millisecond) - 1
        :ets.insert(@table, {:models, list, past})

      [] ->
        :ok
    end

    :ok
  end

  # -- GenServer ---------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call(:refresh, _from, state), do: {:reply, do_refresh(), state}

  @impl true
  def handle_cast(:refresh, state) do
    result = do_refresh()
    EyeInTheSky.Events.pi_models_refreshed(result)
    {:noreply, state}
  end

  defp do_refresh do
    case control_module().discover_models() do
      {:ok, models} when is_list(models) ->
        expires_at = System.monotonic_time(:millisecond) + @ttl_ms
        :ets.insert(@table, {:models, models, expires_at})
        {:ok, models}

      {:error, reason} ->
        Logger.warning(
          "[Pi.ModelDiscoveryCache] refresh failed: " <>
            EyeInTheSky.Redaction.redact_inspect(reason, limit: 200)
        )

        {:error, reason}
    end
  end

  defp safe_lookup do
    case :ets.whereis(@table) do
      :undefined -> []
      _ -> :ets.lookup(@table, :models)
    end
  end

  defp control_module,
    do: Application.get_env(:eye_in_the_sky, :pi_control_module, EyeInTheSky.Pi.Control)
end
