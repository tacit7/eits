defmodule EyeInTheSkyWeb.ChatAgents do
  @moduledoc """
  The ChatAgents context for managing chat agent identities.

  A ChatAgent represents a participant/identity in the chat/DM system,
  distinct from an Agent which is an execution context.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.ChatAgents.ChatAgent

  @doc """
  Returns the list of chat agents.
  """
  def list_chat_agents do
    Repo.all(ChatAgent)
  end

  @doc """
  Returns the list of chat agents with their sessions and tasks preloaded for display.
  Sorted by creation date (most recent first).
  """
  def list_chat_agents_with_sessions do
    ChatAgent
    |> preload([:agents, :tasks, :project])
    |> order_by([a], desc: a.created_at)
    |> Repo.all()
    |> Enum.map(&populate_project_name/1)
  end

  @doc """
  Returns the list of active chat agents.
  """
  def list_active_chat_agents do
    ChatAgent
    |> preload([:project])
    |> order_by([a], desc: a.created_at)
    |> Repo.all()
    |> Enum.map(&populate_project_name/1)
  end

  @doc """
  Returns counts of chat agents by project for overview purposes.
  """
  def get_chat_agent_status_counts(project_id \\ nil) do
    query =
      if project_id do
        from a in ChatAgent, where: a.project_id == ^project_id
      else
        ChatAgent
      end

    query
    |> select([a], count(a.id))
    |> Repo.all()
  end

  @doc """
  Gets a single chat agent.

  Raises `Ecto.NoResultsError` if the ChatAgent does not exist.
  """
  def get_chat_agent!(id) do
    ChatAgent
    |> preload([:project])
    |> Repo.get!(id)
    |> populate_project_name()
  end

  @doc """
  Gets a single chat agent, returning {:ok, chat_agent} or {:error, :not_found}.

  This is the safe version that doesn't raise exceptions.
  """
  def get_chat_agent(id) do
    case ChatAgent
         |> preload([:project])
         |> Repo.get(id) do
      nil -> {:error, :not_found}
      chat_agent -> {:ok, populate_project_name(chat_agent)}
    end
  end

  @doc """
  Gets a single chat agent with all associations preloaded.
  """
  def get_chat_agent_with_associations!(id) do
    ChatAgent
    |> preload([:agents, :tasks, :project])
    |> Repo.get!(id)
    |> populate_project_name()
  end

  @doc """
  Populates the virtual project_name field from the project association.
  """
  def populate_project_name(%ChatAgent{} = chat_agent) do
    project_name =
      case chat_agent.project do
        %{name: name} -> name
        _ -> nil
      end

    Map.put(chat_agent, :project_name, project_name)
  end

  def populate_project_name(chat_agent), do: chat_agent

  @doc """
  Creates a chat agent.
  """
  def create_chat_agent(attrs \\ %{}) do
    %ChatAgent{}
    |> ChatAgent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a chat agent.
  """
  def update_chat_agent(%ChatAgent{} = chat_agent, attrs) do
    chat_agent
    |> ChatAgent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a chat agent (status field moved to sessions).
  """
  def update_chat_agent_status(%ChatAgent{} = chat_agent, _status) do
    {:ok, chat_agent}
  end

  @doc """
  Deletes a chat agent.
  """
  def delete_chat_agent(%ChatAgent{} = chat_agent) do
    Repo.delete(chat_agent)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking chat agent changes.
  """
  def change_chat_agent(%ChatAgent{} = chat_agent, attrs \\ %{}) do
    ChatAgent.changeset(chat_agent, attrs)
  end

  @doc """
  Lists chat agents by project ID.
  """
  def list_chat_agents_by_project(project_id) do
    ChatAgent
    |> where([a], a.project_id == ^project_id)
    |> preload([:project])
    |> order_by([a], asc: a.created_at)
    |> Repo.all()
    |> Enum.map(&populate_project_name/1)
  end

  @doc """
  Lists bookmarked chat agents.
  """
  def list_bookmarked_chat_agents do
    ChatAgent
    |> where([a], a.bookmarked == true)
    |> preload([:project])
    |> order_by([a], desc: a.created_at)
    |> Repo.all()
    |> Enum.map(&populate_project_name/1)
  end

  @doc """
  Gets a single chat agent by UUID.

  Raises `Ecto.NoResultsError` if the ChatAgent does not exist.
  """
  def get_chat_agent_by_uuid!(uuid) do
    ChatAgent
    |> preload([:project])
    |> Repo.get_by!(uuid: uuid)
    |> populate_project_name()
  end

  @doc """
  Gets a single chat agent by UUID, returning {:ok, chat_agent} or {:error, :not_found}.

  This is the safe version that doesn't raise exceptions.
  """
  def get_chat_agent_by_uuid(uuid) do
    case ChatAgent
         |> preload([:project])
         |> Repo.get_by(uuid: uuid) do
      nil -> {:error, :not_found}
      chat_agent -> {:ok, populate_project_name(chat_agent)}
    end
  end

  @doc """
  Gets a single chat agent by UUID with all associations preloaded.
  """
  def get_chat_agent_with_associations_by_uuid!(uuid) do
    ChatAgent
    |> preload([:agents, :tasks, :project])
    |> Repo.get_by!(uuid: uuid)
    |> populate_project_name()
  end

  @doc """
  Gets complete dashboard data for a chat agent.
  Returns chat agent, sessions, and active session.
  """
  def get_chat_agent_dashboard_data(chat_agent_id) do
    alias EyeInTheSkyWeb.Agents

    chat_agent = get_chat_agent_with_associations!(chat_agent_id)
    agents = Agents.list_agents_for_chat_agent(chat_agent_id)
    # Most recent execution agent
    active_execution_agent = List.first(agents)

    %{
      chat_agent: chat_agent,
      sessions: agents,
      active_session: active_execution_agent
    }
  end

  @doc """
  Gets complete dashboard data for a chat agent by UUID.
  Returns chat agent, sessions, and active session.
  """
  def get_chat_agent_dashboard_data_by_uuid(uuid) do
    alias EyeInTheSkyWeb.Agents

    chat_agent = get_chat_agent_with_associations_by_uuid!(uuid)
    agents = Agents.list_agents_for_chat_agent(chat_agent.id)
    active_execution_agent = List.first(agents)

    %{
      chat_agent: chat_agent,
      sessions: agents,
      active_session: active_execution_agent
    }
  end
end
