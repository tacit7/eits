defmodule EyeInTheSky.IAM do
  @moduledoc """
  Context boundary for the IAM policy engine.

  All policy mutations must go through this module so the `PolicyCache` (added
  in Phase 2) stays consistent. Direct `Repo` writes against
  `EyeInTheSky.IAM.Policy` are disallowed — a CI grep check enforces this.

  Phase 1 scope: schema + CRUD only. Cache invalidation hooks into these
  functions in Phase 2; nothing else changes for callers.
  """

  import Ecto.Query, warn: false

  alias EyeInTheSky.IAM.Policy
  alias EyeInTheSky.Repo

  # ── reads ───────────────────────────────────────────────────────────────────

  @doc "List all policies, ordered by priority desc then id asc."
  @spec list_policies() :: [Policy.t()]
  def list_policies do
    Policy
    |> order_by([p], desc: p.priority, asc: p.id)
    |> Repo.all()
  end

  @doc "Fetch a policy by id."
  @spec get_policy(integer()) :: {:ok, Policy.t()} | {:error, :not_found}
  def get_policy(id) do
    case Repo.get(Policy, id) do
      nil -> {:error, :not_found}
      policy -> {:ok, policy}
    end
  end

  @doc "Fetch a system policy by its stable `system_key`."
  @spec get_by_system_key(String.t()) :: {:ok, Policy.t()} | {:error, :not_found}
  def get_by_system_key(system_key) when is_binary(system_key) do
    case Repo.get_by(Policy, system_key: system_key) do
      nil -> {:error, :not_found}
      policy -> {:ok, policy}
    end
  end

  # ── writes (context boundary) ───────────────────────────────────────────────

  @doc "Create a user or system policy."
  @spec create_policy(map()) :: {:ok, Policy.t()} | {:error, Ecto.Changeset.t()}
  def create_policy(attrs) do
    %Policy{}
    |> Policy.create_changeset(attrs)
    |> Repo.insert()
    |> maybe_invalidate_cache()
  end

  @doc "Update an existing policy. Locked-field enforcement runs in the changeset."
  @spec update_policy(Policy.t(), map()) ::
          {:ok, Policy.t()} | {:error, Ecto.Changeset.t()}
  def update_policy(%Policy{} = policy, attrs) do
    policy
    |> Policy.update_changeset(attrs)
    |> Repo.update()
    |> maybe_invalidate_cache()
  end

  @doc "Delete a policy by struct."
  @spec delete_policy(Policy.t()) :: {:ok, Policy.t()} | {:error, Ecto.Changeset.t()}
  def delete_policy(%Policy{} = policy) do
    policy
    |> Repo.delete()
    |> maybe_invalidate_cache()
  end

  @doc """
  Seed a built-in system policy. Seed-once semantics: if a row with the same
  `system_key` already exists, this is a no-op and the existing row is
  returned. To change locked matcher fields on an existing install, ship an
  explicit migration.
  """
  @spec seed_builtin(map()) :: {:ok, Policy.t()} | {:error, Ecto.Changeset.t()}
  def seed_builtin(%{system_key: system_key} = attrs) when is_binary(system_key) do
    case Repo.get_by(Policy, system_key: system_key) do
      nil -> create_policy(attrs)
      %Policy{} = existing -> {:ok, existing}
    end
  end

  @doc "Bulk toggle the `enabled` flag on policies matching the given ids."
  @spec bulk_toggle_enabled([integer()], boolean()) :: {non_neg_integer(), nil | [term()]}
  def bulk_toggle_enabled(ids, enabled) when is_list(ids) and is_boolean(enabled) do
    result =
      from(p in Policy, where: p.id in ^ids)
      |> Repo.update_all(set: [enabled: enabled, updated_at: DateTime.utc_now()])

    invalidate_cache()
    result
  end

  # ── cache hook ──────────────────────────────────────────────────────────────

  defp maybe_invalidate_cache({:ok, _} = result) do
    invalidate_cache()
    result
  end

  defp maybe_invalidate_cache(other), do: other

  defp invalidate_cache, do: EyeInTheSky.IAM.PolicyCache.invalidate()
end
