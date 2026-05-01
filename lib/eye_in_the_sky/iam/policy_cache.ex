defmodule EyeInTheSky.IAM.PolicyCache do
  @moduledoc """
  ETS-backed cache of enabled IAM policies.

  Single-node only in v1. If EITS deploys multi-node, invalidation must
  switch to `Phoenix.PubSub.broadcast/3`; marked as a known scaling checkpoint
  in the IAM plan.

  Invalidation happens **only** through `EyeInTheSky.IAM` context functions —
  every `create_policy`, `update_policy`, `delete_policy`, `seed_builtin`, and
  `bulk_toggle_enabled` call triggers `invalidate/0`.
  """

  use GenServer

  require Logger

  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.Repo

  import Ecto.Query

  @load_limit 5_000

  @table :iam_policy_cache
  @telemetry_hit [:eye_in_the_sky, :iam, :cache, :hit]
  @telemetry_miss [:eye_in_the_sky, :iam, :cache, :miss]

  # ── public API ──────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Return all enabled policies. Warms the cache on miss.

  Also returns whether the call was a cache hit, for telemetry attribution by
  the evaluator.
  """
  @spec all_enabled() :: {[Policy.t()], :hit | :miss}
  def all_enabled do
    case :ets.lookup(@table, :enabled_policies) do
      [{:enabled_policies, policies}] ->
        :telemetry.execute(@telemetry_hit, %{count: 1}, %{})
        {policies, :hit}

      [] ->
        :telemetry.execute(@telemetry_miss, %{count: 1}, %{})
        policies = load_from_db()
        :ets.insert(@table, {:enabled_policies, policies})
        {policies, :miss}
    end
  end

  @doc "Clear the cache so the next read re-loads from DB."
  @spec invalidate() :: :ok
  def invalidate do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _tid -> :ets.delete(@table, :enabled_policies)
    end

    :ok
  end

  # ── GenServer impl ──────────────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  # ── private ─────────────────────────────────────────────────────────────────

  defp load_from_db do
    policies =
      Policy
      |> where([p], p.enabled == true)
      |> limit(@load_limit)
      |> Repo.all()

    if length(policies) >= @load_limit do
      Logger.warning(
        "IAM policy_cache: LIMIT reached (#{@load_limit}) — some policies may not be evaluated"
      )
    end

    policies
  end
end
