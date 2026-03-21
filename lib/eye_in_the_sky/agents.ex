defmodule EyeInTheSky.Agents do
  @moduledoc """
  The Agents context for managing agent identities.

  An Agent represents a participant/identity in the chat/DM system.
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Agents.Agent

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Agents.Agent

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
  """
  def list_active_agents do
    Agent
    |> preload([:project])
    |> order_by([a], desc: a.created_at)
    |> Repo.all()
    |> Enum.map(&populate_project_name/1)
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
  Gets a single agent.

  Raises `Ecto.NoResultsError` if the Agent does not exist.
  """
  @spec get_agent!(integer()) :: Agent.t()
  def get_agent!(id) do
    Agent
    |> preload([:project])
    |> Repo.get!(id)
    |> populate_project_name()
  end

  @doc """
  Gets a single agent, returning {:ok, agent} or {:error, :not_found}.

  This is the safe version that doesn't raise exceptions.
  """
  @spec get_agent(integer()) :: {:ok, Agent.t()} | {:error, :not_found}
  def get_agent(id) do
    case Agent
         |> preload([:project])
         |> Repo.get(id) do
      nil -> {:error, :not_found}
      agent -> {:ok, populate_project_name(agent)}
    end
  end

  @doc """
  Gets a single agent with all associations preloaded.
  """
  def get_agent_with_associations!(id) do
    Agent
    |> preload([:sessions, :tasks, :project])
    |> Repo.get!(id)
    |> populate_project_name()
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
  Updates an agent.
  """
  @spec update_agent(Agent.t(), map()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def update_agent(%Agent{} = agent, attrs) do
    result = agent |> Agent.changeset(attrs) |> Repo.update()
    with {:ok, updated} <- result, do: EyeInTheSky.Events.agent_updated(updated)
    result
  end

  @doc """
  No-op. Agent status is tracked on the Session, not the Agent.
  Use `Sessions.update_session/2` with `%{status: status}` instead.

  @deprecated
  """
  def update_agent_status(%Agent{} = agent, _status) do
    {:ok, agent}
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
  Lists bookmarked agents.
  """
  def list_bookmarked_agents do
    Agent
    |> where([a], a.bookmarked == true)
    |> preload([:project])
    |> order_by([a], desc: a.created_at)
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

  @doc """
  Gets a single agent by UUID with all associations preloaded.
  """
  def get_agent_with_associations_by_uuid!(uuid) do
    Agent
    |> preload([:sessions, :tasks, :project])
    |> Repo.get_by!(uuid: uuid)
    |> populate_project_name()
  end

  @doc """
  Gets complete dashboard data for an agent.
  Returns agent, sessions, and active session.
  """
  def get_agent_dashboard_data(agent_id) do
    alias EyeInTheSky.Sessions

    agent = get_agent_with_associations!(agent_id)
    sessions = Sessions.list_sessions_for_agent(agent_id)
    # Most recent session
    active_session = List.first(sessions)

    %{
      agent: agent,
      sessions: sessions,
      active_session: active_session
    }
  end

  @doc """
  Gets complete dashboard data for an agent by UUID.
  Returns agent, sessions, and active session.
  """
  def get_agent_dashboard_data_by_uuid(uuid) do
    alias EyeInTheSky.Sessions

    agent = get_agent_with_associations_by_uuid!(uuid)
    sessions = Sessions.list_sessions_for_agent(agent.id)
    active_session = List.first(sessions)

    %{
      agent: agent,
      sessions: sessions,
      active_session: active_session
    }
  end
end
