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
  alias EyeInTheSky.IAM.PolicyCache
  alias EyeInTheSky.IAM.PolicyDocument
  alias EyeInTheSky.IAM.DocumentPolicy
  alias EyeInTheSky.IAM.AgentTypeDocument
  alias EyeInTheSky.Repo

  @typedoc """
  A policy that contributes to evaluation via a document attachment.
  Returned by `policies_for_agent_type/1` and cached by `PolicyCache.for_agent_type/1`.
  """
  @type document_policy_candidate :: %{
          policy: Policy.t(),
          document: PolicyDocument.t(),
          attached_agent_type: String.t()
        }

  # ── reads ───────────────────────────────────────────────────────────────────

  @doc "List all policies, ordered by priority desc then id asc. Capped at 500 rows."
  @spec list_policies() :: [Policy.t()]
  def list_policies do
    Policy
    |> order_by([p], desc: p.priority, asc: p.id)
    |> limit(500)
    |> Repo.all()
  end

  @doc """
  List policies filtered by any of `:agent_type`, `:action`, `:effect`, or
  `:enabled`. A `nil` or empty-string filter is a no-op; other values are
  exact-match. Capped at 500 rows by default; pass `limit: N` to override.
  """
  @spec list_policies(map() | keyword()) :: [Policy.t()]
  def list_policies(filters) when is_list(filters) or is_map(filters) do
    {limit, filters} =
      if is_list(filters) do
        {Keyword.get(filters, :limit, 500), Keyword.delete(filters, :limit)}
      else
        {Map.get(filters, :limit, 500), Map.delete(filters, :limit)}
      end

    filters
    |> Enum.reduce(Policy, fn
      {_key, nil}, q -> q
      {_key, ""}, q -> q
      {:agent_type, v}, q -> where(q, [p], p.agent_type == ^v)
      {:action, v}, q -> where(q, [p], p.action == ^v)
      {:effect, v}, q -> where(q, [p], p.effect == ^v)
      {:enabled, v}, q when is_boolean(v) -> where(q, [p], p.enabled == ^v)
      {_, _}, q -> q
    end)
    |> order_by([p], desc: p.priority, asc: p.id)
    |> limit(^limit)
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

  # ── audit ────────────────────────────────────────────────────────────────────

  @doc "Persist an IAM decision audit record. Async in production; synchronous in test to avoid sandbox teardown races."
  def record_audit(ctx, decision, raw_payload, duration_us) do
    if Application.get_env(:eye_in_the_sky, :iam_audit_sync, false) do
      do_write_audit(ctx, decision, raw_payload, duration_us)
    else
      Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
        do_write_audit(ctx, decision, raw_payload, duration_us)
      end)
    end
  end

  defp do_write_audit(ctx, decision, raw_payload, duration_us) do
    decision_id = Ecto.UUID.dump!(Ecto.UUID.generate())

    session_uuid_bin =
      case ctx.session_uuid do
        nil -> nil
        uuid -> Ecto.UUID.dump!(uuid)
      end

    instructions_snapshot =
      Enum.map(decision.instructions, fn %{policy: p, message: msg} ->
        %{
          "policy_id" => p.id,
          "system_key" => p.system_key,
          "name" => p.name,
          "message" => msg
        }
      end)

    {winning_policy_id, winning_system_key, winning_name} =
      case decision.winning_policy do
        nil -> {nil, nil, nil}
        p -> {p.id, p.system_key, p.name}
      end

    row = %{
      decision_id: decision_id,
      session_uuid: session_uuid_bin,
      event: to_string(ctx.event),
      agent_type: ctx.agent_type,
      project_id: ctx.project_id,
      project_path: ctx.project_path,
      tool: ctx.tool,
      resource_path: ctx.resource_path,
      permission: to_string(decision.permission),
      default: decision.default?,
      winning_policy_id: winning_policy_id,
      winning_policy_system_key: winning_system_key,
      winning_policy_name: winning_name,
      reason: decision.reason,
      instructions_snapshot: instructions_snapshot,
      evaluated_count: decision.evaluated_count,
      duration_us: duration_us,
      raw_payload: raw_payload,
      inserted_at: DateTime.utc_now()
    }

    Repo.insert_all("iam_decisions", [row])
  end

  # ── policy documents ─────────────────────────────────────────────────────────

  @doc "List all policy documents ordered by name."
  @spec list_policy_documents() :: [PolicyDocument.t()]
  def list_policy_documents do
    PolicyDocument
    |> order_by([d], asc: d.name)
    |> Repo.all()
  end

  @doc """
  Fetch a policy document by id. Pass `preload: [...]` to eager-load associations.

      get_policy_document(id, preload: [:document_policies, :agent_type_documents])
  """
  @spec get_policy_document(integer(), keyword()) ::
          {:ok, PolicyDocument.t()} | {:error, :not_found}
  def get_policy_document(id, opts \\ []) do
    preloads = Keyword.get(opts, :preload, [])

    case Repo.get(PolicyDocument, id) do
      nil -> {:error, :not_found}
      doc -> {:ok, Repo.preload(doc, preloads)}
    end
  end

  @doc "Create a policy document."
  @spec create_policy_document(map()) :: {:ok, PolicyDocument.t()} | {:error, Ecto.Changeset.t()}
  def create_policy_document(attrs) do
    %PolicyDocument{}
    |> PolicyDocument.create_changeset(attrs)
    |> Repo.insert()
    |> maybe_invalidate_cache()
  end

  @doc "Update an existing policy document."
  @spec update_policy_document(PolicyDocument.t(), map()) ::
          {:ok, PolicyDocument.t()} | {:error, Ecto.Changeset.t()}
  def update_policy_document(%PolicyDocument{} = doc, attrs) do
    doc
    |> PolicyDocument.update_changeset(attrs)
    |> Repo.update()
    |> maybe_invalidate_cache()
  end

  @doc "Delete a policy document. Cascades to document_policies and agent_type_documents."
  @spec delete_policy_document(PolicyDocument.t()) ::
          {:ok, PolicyDocument.t()} | {:error, Ecto.Changeset.t()}
  def delete_policy_document(%PolicyDocument{} = doc) do
    doc
    |> Repo.delete()
    |> maybe_invalidate_cache()
  end

  @doc """
  Attach a policy to a document.

  Returns `{:error, :document_not_found}` or `{:error, :policy_not_found}` if
  either entity is missing. Returns `{:error, :already_attached}` if the pair
  already exists (unique constraint). Invalidates the cache on success.
  """
  @spec add_policy_to_document(integer(), integer()) ::
          {:ok, DocumentPolicy.t()}
          | {:error, :document_not_found | :policy_not_found | :already_attached | Ecto.Changeset.t()}
  def add_policy_to_document(document_id, policy_id) do
    with {:doc, %PolicyDocument{}} <- {:doc, Repo.get(PolicyDocument, document_id)},
         {:policy, %Policy{}} <- {:policy, Repo.get(Policy, policy_id)} do
      result =
        Repo.transaction(fn ->
          %DocumentPolicy{}
          |> DocumentPolicy.changeset(%{document_id: document_id, policy_id: policy_id})
          |> Repo.insert()
        end)

      case result do
        {:ok, {:ok, dp}} ->
          invalidate_cache()
          {:ok, dp}

        {:ok, {:error, changeset}} ->
          if unique_violation?(changeset, :iam_document_policies_unique) do
            {:error, :already_attached}
          else
            {:error, changeset}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:doc, nil} -> {:error, :document_not_found}
      {:policy, nil} -> {:error, :policy_not_found}
    end
  end

  @doc """
  Remove a policy from a document. Returns `:ok` or `{:error, :not_found}`.
  Invalidates the cache on success.
  """
  @spec remove_policy_from_document(integer(), integer()) :: :ok | {:error, :not_found}
  def remove_policy_from_document(document_id, policy_id) do
    case Repo.get_by(DocumentPolicy, document_id: document_id, policy_id: policy_id) do
      nil ->
        {:error, :not_found}

      %DocumentPolicy{} = dp ->
        Repo.delete!(dp)
        invalidate_cache()
        :ok
    end
  end

  @doc """
  Return all agent types that have at least one document attached, grouped as
  `[{agent_type, [PolicyDocument.t()]}]` ordered by agent_type.
  """
  @spec list_agent_types_with_documents() :: [{String.t(), [PolicyDocument.t()]}]
  def list_agent_types_with_documents do
    rows =
      AgentTypeDocument
      |> order_by([a], asc: a.agent_type)
      |> preload(:document)
      |> Repo.all()

    rows
    |> Enum.group_by(& &1.agent_type, & &1.document)
    |> Enum.sort_by(fn {agent_type, _} -> agent_type end)
  end

  @doc """
  Attach a policy document to an agent type string.

  Returns `{:error, :document_not_found}` if the document does not exist.
  Returns `{:error, :already_attached}` if the pair already exists.
  Invalidates the cache on success.
  """
  @spec attach_document_to_agent_type(String.t(), integer()) ::
          {:ok, AgentTypeDocument.t()}
          | {:error, :document_not_found | :already_attached | Ecto.Changeset.t()}
  def attach_document_to_agent_type(agent_type, document_id) do
    case Repo.get(PolicyDocument, document_id) do
      nil ->
        {:error, :document_not_found}

      %PolicyDocument{} ->
        result =
          Repo.transaction(fn ->
            %AgentTypeDocument{}
            |> AgentTypeDocument.changeset(%{agent_type: agent_type, document_id: document_id})
            |> Repo.insert()
          end)

        case result do
          {:ok, {:ok, atd}} ->
            invalidate_cache()
            {:ok, atd}

          {:ok, {:error, changeset}} ->
            if unique_violation?(changeset, :iam_agent_type_documents_unique) do
              {:error, :already_attached}
            else
              {:error, changeset}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Detach a policy document from an agent type. Returns `:ok` or `{:error, :not_found}`.
  Invalidates the cache on success.
  """
  @spec detach_document_from_agent_type(String.t(), integer()) :: :ok | {:error, :not_found}
  def detach_document_from_agent_type(agent_type, document_id) do
    case Repo.get_by(AgentTypeDocument, agent_type: agent_type, document_id: document_id) do
      nil ->
        {:error, :not_found}

      %AgentTypeDocument{} = atd ->
        Repo.delete!(atd)
        invalidate_cache()
        :ok
    end
  end

  @doc """
  Return all enabled policies contributed by documents attached to the given agent type.

  Each result is a `document_policy_candidate` map:

      %{policy: %Policy{}, document: %PolicyDocument{}, attached_agent_type: "code-reviewer"}

  Always returns a list — never an error tuple. Unknown or unattached agent types return `[]`.
  """
  @spec policies_for_agent_type(String.t()) :: [document_policy_candidate()]
  def policies_for_agent_type(agent_type) when is_binary(agent_type) do
    from(atd in AgentTypeDocument,
      where: atd.agent_type == ^agent_type,
      join: doc in assoc(atd, :document),
      join: dp in assoc(doc, :document_policies),
      join: p in assoc(dp, :policy),
      where: p.enabled == true,
      select: %{
        policy: p,
        document: doc,
        attached_agent_type: atd.agent_type
      }
    )
    |> Repo.all()
  end

  # ── private helpers ──────────────────────────────────────────────────────────

  defp unique_violation?(%Ecto.Changeset{errors: errors}, constraint_name) do
    Enum.any?(errors, fn {_field, {_msg, opts}} ->
      opts[:constraint] == :unique and opts[:constraint_name] == constraint_name
    end)
  end

  # ── cache hook ──────────────────────────────────────────────────────────────

  defp maybe_invalidate_cache({:ok, _} = result) do
    invalidate_cache()
    result
  end

  defp maybe_invalidate_cache(other), do: other

  defp invalidate_cache, do: PolicyCache.invalidate()
end
