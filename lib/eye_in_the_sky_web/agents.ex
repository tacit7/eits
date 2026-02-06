defmodule EyeInTheSkyWeb.Agents do
  @moduledoc """
  The Agents context for managing agents and their lifecycle.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Agents.Agent

  @doc """
  Returns the list of agents.
  """
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
  Returns counts of agents by project for overview purposes.
  """
  def get_agent_status_counts(project_id \\ nil) do
    query =
      if project_id do
        from a in Agent, where: a.project_id == ^project_id
      else
        Agent
      end

    query
    |> select([a], count(a.id))
    |> Repo.all()
  end

  @doc """
  Gets a single agent.

  Raises `Ecto.NoResultsError` if the Agent does not exist.
  """
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
  Populates the virtual project_name field from the project association.
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
  def create_agent(attrs \\ %{}) do
    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an agent.
  """
  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates an agent (status field moved to sessions).
  """
  def update_agent_status(%Agent{} = agent, _status) do
    {:ok, agent}
  end

  @doc """
  Deletes an agent.
  """
  def delete_agent(%Agent{} = agent) do
    Repo.delete(agent)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking agent changes.
  """
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
  Gets complete dashboard data for an agent.
  Returns agent, sessions, and active session.
  """
  def get_agent_dashboard_data(agent_id) do
    alias EyeInTheSkyWeb.Sessions

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
end
