defmodule EyeInTheSky.Agents do
  @moduledoc """
  The Agents context for managing agent identities.

  An Agent represents a participant/identity in the chat/DM system.
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Agents.Agent

  import Ecto.Query, warn: false
  alias EyeInTheSky.Agents.Agent
  alias EyeInTheSky.Repo

  @doc """
  Returns the list of agents.
  """
  @spec list_agents() :: [Agent.t()]
  def list_agents do
    Repo.all(Agent)
  end

  @doc """
  Returns the list of agents with their sessions and tasks preloaded for display.
  Sorted by creation date (most recent first).
  """
  def list_agents_with_sessions do
    Agent
    |> preload([:sessions, :tasks, :project])
    |> order_by([a], desc: a.created_at)
    |> Repo.all()
    |> Enum.map(&populate_project_name/1)
  end

  @doc """
  Returns the list of active agents.
  Active agents are those whose status is not "completed" or "failed".
  """
  def list_active_agents do
    Agent
    |> where([a], a.status not in ["completed", "failed"])
    |> preload([:project])
    |> order_by([a], desc: a.created_at)
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
    result = %Agent{} |> Agent.changeset(attrs) |> Repo.insert()
    with {:ok, agent} <- result, do: EyeInTheSky.Events.agent_created(agent)
    result
  end

  @doc """
  Finds an agent by UUID or creates one with the given attrs.
  Uses on_conflict: :nothing to handle UUID uniqueness races without exceptions.
  """
  def find_or_create_agent(%{uuid: uuid} = attrs) do
    case get_agent_by_uuid(uuid) do
      {:ok, existing} ->
        {:ok, existing}

      {:error, :not_found} ->
        %Agent{}
        |> Agent.changeset(attrs)
        |> Repo.insert(on_conflict: :nothing, conflict_target: :uuid)
        |> case do
          {:ok, %Agent{id: nil}} ->
            # on_conflict: :nothing means no row returned; re-fetch the winner
            get_agent_by_uuid(uuid)

          {:ok, agent} ->
            EyeInTheSky.Events.agent_created(agent)
            {:ok, agent}

          {:error, _changeset} = err ->
            err
        end
    end
  end

  @doc """
  Updates an agent.
  """
  @spec update_agent(Agent.t(), map()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def update_agent(%Agent{} = agent, attrs) do
    result = agent |> Agent.changeset(attrs) |> Repo.update()
    with {:ok, updated} <- result, do: EyeInTheSky.Events.agent_updated(updated)
    result
  end

  @doc """
  Returns agents whose status is not "completed" or "failed".
  Used by the scheduler to check agents that may need status updates.
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
    result = Repo.delete(agent)
    with {:ok, deleted} <- result, do: EyeInTheSky.Events.agent_deleted(deleted)
    result
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking agent changes.
  """
  @spec change_agent(Agent.t(), map()) :: Ecto.Changeset.t()
  def change_agent(%Agent{} = agent, attrs \\ %{}) do
    Agent.changeset(agent, attrs)
  end

  @doc """
  Lists agents by project ID.
  """
  def list_agents_by_project(project_id) do
    Agent
    |> where([a], a.project_id == ^project_id)
    |> preload([:project])
    |> order_by([a], asc: a.created_at)
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
end
