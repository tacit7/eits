defmodule EyeInTheSky.Agents do
  @moduledoc """
  The Agents context for managing agent identities.

  An Agent represents a participant/identity in the chat/DM system.
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Agents.Agent

  import Ecto.Query, warn: false
  alias EyeInTheSky.Agents.Agent
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Settings.JsonSettings

  @doc """
  Returns the list of agents. Default limit: 500.
  Pass `limit: n` to override.
  """
  @spec list_agents(keyword()) :: [Agent.t()]
  def list_agents(opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    Agent
    |> EyeInTheSky.QueryBuilder.maybe_where(opts, :status)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns agents with their sessions preloaded, capped at 200 rows.
  Sorted by creation date (most recent first).

  Only `:sessions` is preloaded — `:tasks` and `:project` were previously
  included but are not consumed by any caller.
  """
  def list_agents_with_sessions do
    # L3 fix: cap sessions preload to 10 most-recent per agent.
    # An unbounded preload on 200 agents could load thousands of session rows.
    recent_sessions = from(s in Session, order_by: [desc: s.started_at], limit: 10)

    Agent
    |> preload(sessions: ^recent_sessions)
    |> order_by([a], desc: a.created_at)
    |> limit(200)
    |> Repo.all()
    |> Enum.map(&populate_project_name/1)
  end

  def list_agent_templates(limit \\ 50) do
    Agent
    |> where([a], a.status not in ["completed", "failed"])
    |> where([a], not is_nil(a.description) and a.description != "")
    |> order_by([a], desc: a.created_at)
    |> limit(^limit)
    |> select([a], %{id: a.id, description: a.description})
    |> Repo.all()
  end

  @doc """
  Returns the total agent count, optionally scoped to a project.
  """
  def get_agent_status_counts(project_id \\ nil) do
    query =
      if project_id do
        from a in Agent, where: a.project_id == ^project_id
      else
        Agent
      end

    Repo.aggregate(query, :count, :id)
  end

  @doc """
  Returns `{total_count, working_count}` for agents in a project.
  Single aggregate query — use instead of loading all agents just to count them.
  """
  def count_agents_for_project(project_id) do
    result =
      Repo.one(
        from a in Agent,
          where: a.project_id == ^project_id,
          select: {
            count(a.id),
            sum(fragment("CASE WHEN ? = 'working' THEN 1 ELSE 0 END", a.status))
          }
      )

    case result do
      {total, nil} -> {total, 0}
      {total, working} -> {total, working}
      nil -> {0, 0}
    end
  end

  @doc """
  Gets a single agent.

  Raises `Ecto.NoResultsError` if the Agent does not exist.
  """
  @spec get_agent!(integer()) :: Agent.t()
  def get_agent!(id) do
    base_agent_query()
    |> Repo.get!(id)
    |> populate_project_name()
  end

  @doc """
  Gets a single agent, returning {:ok, agent} or {:error, :not_found}.

  This is the safe version that doesn't raise exceptions.
  """
  @spec get_agent(integer()) :: {:ok, Agent.t()} | {:error, :not_found}
  def get_agent(id) do
    case base_agent_query()
         |> Repo.get(id) do
      nil -> {:error, :not_found}
      agent -> {:ok, populate_project_name(agent)}
    end
  end

  @doc """
  Denormalization helper: copies project.name into agent.project_name.

  `project_name` is a real DB column, but it is never written by the
  application — it exists for external/legacy readers. At runtime we derive
  the value from the preloaded `project` association and store it in the
  struct field so callers can read it without an extra query.

  Call this after any `Repo.get/list` that preloads `:project`. It is safe
  to call on a bare map or a non-Agent value; the fallback clause is a no-op.
  """
  def populate_project_name(%Agent{} = agent) do
    project_name =
      case agent.project do
        %{name: name} -> name
        _ -> nil
      end

    Map.put(agent, :project_name, project_name)
  end

  def populate_project_name(agent), do: agent

  @doc """
  Creates an agent.
  """
  @spec create_agent(map()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def create_agent(attrs \\ %{}) do
    %Agent{} |> Agent.changeset(attrs) |> Repo.insert() |> broadcast_result(&EyeInTheSky.Events.agent_created/1)
  end

  @doc """
  Finds an agent by UUID or creates one with the given attrs.
  Uses on_conflict: :nothing to handle UUID uniqueness races without exceptions.
  """
  def find_or_create_agent(%{uuid: uuid} = attrs) do
    case Repo.insert(
           Agent.changeset(%Agent{}, attrs),
           on_conflict: [set: [uuid: uuid]],
           conflict_target: :uuid,
           returning: true
         ) do
      {:ok, agent} ->
        # inserted_at == updated_at only on a fresh insert; the no-op uuid update
        # touches updated_at on conflict, so we can reliably detect new rows here.
        if DateTime.compare(agent.inserted_at, agent.updated_at) == :eq do
          EyeInTheSky.Events.agent_created(agent)
        end

        {:ok, agent}

      {:error, _changeset} = err ->
        err
    end
  end

  @doc """
  Updates an agent.
  """
  @spec update_agent(Agent.t(), map()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def update_agent(%Agent{} = agent, attrs) do
    agent |> Agent.changeset(attrs) |> Repo.update() |> broadcast_result(&EyeInTheSky.Events.agent_updated/1)
  end

  @doc """
  Returns agents whose status is not "completed" or "failed".
  Used by the scheduler to check agents that may need status updates.

  Intentionally has no LIMIT — the scheduler must process every non-terminal
  agent on each 5-minute tick to keep status accurate. If the agent count grows
  to tens of thousands, revisit with cursor-based pagination in the scheduler.
  """
  def list_agents_pending_status_check do
    Agent
    |> where([a], a.status not in ["completed", "failed"])
    |> Repo.all()
  end

  @doc """
  Archives an agent by setting its archived_at timestamp.
  """
  def archive_agent(%Agent{} = agent, now) do
    agent
    |> Agent.changeset(%{archived_at: now})
    |> Repo.update()
  end

  @doc """
  Deletes an agent.
  """
  @spec delete_agent(Agent.t()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def delete_agent(%Agent{} = agent) do
    Repo.delete(agent) |> broadcast_result(&EyeInTheSky.Events.agent_deleted/1)
  end

  defp broadcast_result({:ok, record} = result, event_fn) do
    event_fn.(record)
    result
  end

  defp broadcast_result(result, _event_fn), do: result

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking agent changes.
  """
  @spec change_agent(Agent.t(), map()) :: Ecto.Changeset.t()
  def change_agent(%Agent{} = agent, attrs \\ %{}) do
    Agent.changeset(agent, attrs)
  end

  @doc """
  Returns agents that have had session activity at or after `since_dt`.
  Matches agents with sessions where last_activity_at >= since OR inserted_at >= since.
  Default limit: 200. Pass `limit: n` to override.
  """
  def list_agents_active_since(%DateTime{} = since_dt, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    from(a in Agent,
      join: s in assoc(a, :sessions),
      where: s.last_activity_at >= ^since_dt or s.inserted_at >= ^since_dt,
      distinct: true,
      preload: [:project]
    )
    |> EyeInTheSky.QueryBuilder.maybe_where(opts, :status)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&populate_project_name/1)
  end

  @doc """
  Lists agents by project ID. Default limit: 200.
  Pass `limit: n` to override.
  """
  def list_agents_by_project(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    Agent
    |> where([a], a.project_id == ^project_id)
    |> preload([:project])
    |> order_by([a], asc: a.created_at)
    |> EyeInTheSky.QueryBuilder.maybe_where(opts, :status)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&populate_project_name/1)
  end

  @doc """
  Gets a single agent by UUID.

  Raises `Ecto.NoResultsError` if the Agent does not exist.
  """
  def get_agent_by_uuid!(uuid) do
    Agent
    |> preload([:project])
    |> Repo.get_by!(uuid: uuid)
    |> populate_project_name()
  end

  @doc """
  Gets a single agent by UUID, returning {:ok, agent} or {:error, :not_found}.

  This is the safe version that doesn't raise exceptions.
  """
  def get_agent_by_uuid(uuid) do
    case Agent
         |> preload([:project])
         |> Repo.get_by(uuid: uuid) do
      nil -> {:error, :not_found}
      agent -> {:ok, populate_project_name(agent)}
    end
  end

  @doc "Preloads associations onto an agent struct. Defaults to [:sessions, :project]."
  def preload_agent_associations(%Agent{} = agent, assocs \\ [:sessions, :project]) do
    Repo.preload(agent, assocs)
  end

  defp base_agent_query do
    from(a in Agent, preload: [:project, :agent_definition])
  end

  # ---------------------------------------------------------------------------
  # JSONB settings overrides (agents.settings)
  #
  # Stores agent-level defaults that apply to every session spawned from this
  # agent unless overridden at the session level. See
  # EyeInTheSky.Settings.JsonSettings.effective_settings/2.
  # ---------------------------------------------------------------------------

  @doc "Read a single override on this agent (no defaults applied)."
  def get_setting(%Agent{} = agent, dotted_key) when is_binary(dotted_key) do
    JsonSettings.get_setting(agent.settings || %{}, dotted_key)
  end

  @doc "Coerce + persist a single agent-level override."
  def put_setting(%Agent{} = agent, dotted_key, value) do
    case JsonSettings.coerce_value(value, dotted_key, :agent) do
      {:ok, coerced} ->
        updated_settings = JsonSettings.put_setting(agent.settings || %{}, dotted_key, coerced)
        persist_settings(agent, updated_settings)

      {:error, _reason} = err ->
        err
    end
  end

  @doc "Remove a single override. Effective value falls back to app default."
  def delete_setting(%Agent{} = agent, dotted_key) do
    updated_settings = JsonSettings.delete_setting(agent.settings || %{}, dotted_key)
    persist_settings(agent, updated_settings)
  end

  @doc "Drop an entire namespace of overrides."
  def reset_settings_namespace(%Agent{} = agent, namespace) do
    updated_settings = JsonSettings.reset_namespace(agent.settings || %{}, namespace)
    persist_settings(agent, updated_settings)
  end

  @doc "Clear all agent-level overrides."
  def reset_settings(%Agent{} = agent) do
    persist_settings(agent, %{})
  end

  defp persist_settings(%Agent{} = agent, settings) when is_map(settings) do
    agent
    |> Agent.changeset(%{settings: settings})
    |> Repo.update()
  end
end
