defmodule EyeInTheSkyWeb.ExecutionAgents do
  @moduledoc """
  The ExecutionAgents context for managing autonomous execution units.

  An ExecutionAgent represents an autonomous Claude process doing work,
  distinct from a ChatAgent which is a chat identity/member.

  Temporary naming during Step 2 migration. Will be renamed to Agents in Step 8.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.ExecutionAgents.ExecutionAgent
  alias EyeInTheSkyWeb.Scopes.Archivable

  @doc """
  Returns the list of execution agents, excluding archived by default.
  Pass `include_archived: true` to include archived execution agents.
  """
  def list_execution_agents(opts \\ []) do
    ExecutionAgent
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Returns the list of execution agents for a specific chat agent, excluding archived by default.
  Pass `include_archived: true` to include archived execution agents.
  """
  def list_execution_agents_for_chat_agent(chat_agent_id, opts \\ []) do
    ExecutionAgent
    |> where([ea], ea.agent_id == ^chat_agent_id)
    |> order_by([ea], desc: ea.started_at)
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Gets a single execution agent.

  Raises `Ecto.NoResultsError` if the ExecutionAgent does not exist.
  """
  def get_execution_agent!(id) do
    Repo.get!(ExecutionAgent, id)
  end

  @doc """
  Gets a single execution agent by UUID.

  Raises `Ecto.NoResultsError` if the ExecutionAgent does not exist.
  """
  def get_execution_agent_by_uuid!(uuid) do
    Repo.get_by!(ExecutionAgent, uuid: uuid)
  end

  @doc """
  Gets a single execution agent by UUID, returning {:ok, agent} or {:error, :not_found}.

  This is the safe version that doesn't raise exceptions.
  """
  def get_execution_agent_by_uuid(uuid) do
    case Repo.get_by(ExecutionAgent, uuid: uuid) do
      nil -> {:error, :not_found}
      agent -> {:ok, agent}
    end
  end

  @doc """
  Gets a single execution agent, returning {:ok, agent} or {:error, :not_found}.

  This is the safe version that doesn't raise exceptions.
  """
  def get_execution_agent(id) do
    case Repo.get(ExecutionAgent, id) do
      nil -> {:error, :not_found}
      agent -> {:ok, agent}
    end
  end

  @doc """
  Gets a single execution agent with logs preloaded.
  """
  def get_execution_agent_with_logs!(id) do
    ExecutionAgent
    |> preload(:logs)
    |> Repo.get!(id)
  end

  @doc """
  Creates an execution agent.
  """
  def create_execution_agent(attrs \\ %{}) do
    %ExecutionAgent{}
    |> ExecutionAgent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an execution agent with model tracking information.

  Requires model_provider and model_name in attrs.
  Model info is immutable after creation.

  Returns {:ok, agent} or {:error, changeset}.
  """
  def create_execution_agent_with_model(attrs \\ %{}) do
    %ExecutionAgent{}
    |> ExecutionAgent.creation_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an execution agent, but prevents modification of model fields.

  Model information is immutable per execution agent.
  Attempting to change model_provider or model_name will be ignored.
  """
  def update_execution_agent(%ExecutionAgent{} = agent, attrs) do
    # Remove model fields if present - they are immutable
    attrs =
      attrs
      |> Map.delete(:model_provider)
      |> Map.delete(:model_name)
      |> Map.delete(:model_version)

    agent
    |> ExecutionAgent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Ends an execution agent by setting ended_at timestamp.
  """
  def end_execution_agent(%ExecutionAgent{} = agent) do
    update_execution_agent(agent, %{ended_at: DateTime.utc_now()})
  end

  @doc """
  Archives an execution agent (soft delete).
  """
  def archive_execution_agent(%ExecutionAgent{} = agent) do
    now = DateTime.utc_now() |> DateTime.to_string()
    update_execution_agent(agent, %{archived_at: now})
  end

  @doc """
  Unarchives an execution agent.
  """
  def unarchive_execution_agent(%ExecutionAgent{} = agent) do
    require Logger
    Logger.info("📦 Unarchiving execution agent #{agent.id}, current archived_at: #{inspect(agent.archived_at)}")
    result = update_execution_agent(agent, %{archived_at: nil})
    Logger.info("📦 Update result: #{inspect(result)}")
    result
  end

  @doc """
  Deletes an execution agent (hard delete).
  """
  def delete_execution_agent(%ExecutionAgent{} = agent) do
    Repo.delete(agent)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking execution agent changes.
  """
  def change_execution_agent(%ExecutionAgent{} = agent, attrs \\ %{}) do
    ExecutionAgent.changeset(agent, attrs)
  end

  @doc """
  Lists active execution agents (not ended and not archived), excluding archived by default.
  Pass `include_archived: true` to include archived execution agents.
  """
  def list_active_execution_agents(opts \\ []) do
    ExecutionAgent
    |> where([ea], is_nil(ea.ended_at))
    |> order_by([ea], desc: ea.started_at)
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Lists all execution agents with chat agent preloaded for the overview page.
  Returns agents ordered by most recent first, excluding archived by default.
  Pass `include_archived: true` to include archived execution agents.
  """
  def list_execution_agents_with_chat_agent(opts \\ []) do
    ExecutionAgent
    |> preload(:chat_agent)
    |> order_by([ea], desc: ea.started_at)
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Lists execution agents filtered by search query and status filter using FTS5 full-text search.
  Only returns active (non-archived) execution agents.

  Options:
  - `:search_query` - String to search across agent name, description, project name, agent ID, chat agent description
  - `:status_filter` - One of: "all", "active", "completed", "stale", "discovered"
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Number of results to skip (default: 0)
  """
  def list_execution_agents_filtered(opts \\ []) do
    search_query = Keyword.get(opts, :search_query, "")
    status_filter = Keyword.get(opts, :status_filter, "active")
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    base_query =
      from ea in ExecutionAgent,
        join: ca in assoc(ea, :chat_agent),
        where: is_nil(ea.archived_at),
        preload: [chat_agent: ca],
        order_by: [desc: ea.started_at],
        limit: ^limit,
        offset: ^offset

    # Apply FTS5 search filter
    base_query =
      if search_query != "" do
        # Use FTS5 MATCH query for full-text search
        fts_query = prepare_fts_query(search_query)

        where(
          base_query,
          [ea, ca],
          fragment(
            "EXISTS (SELECT 1 FROM sessions_fts WHERE sessions_fts.rowid = ?.rowid AND sessions_fts MATCH ?)",
            ea,
            ^fts_query
          )
        )
      else
        base_query
      end

    # Apply status filter
    base_query =
      case status_filter do
        "active" ->
          where(base_query, [ea, ca], is_nil(ea.ended_at) and ca.status != "discovered")

        "completed" ->
          where(base_query, [ea], not is_nil(ea.ended_at))

        "stale" ->
          where(base_query, [ea, ca], is_nil(ea.ended_at) and ca.status == "stale")

        "discovered" ->
          where(base_query, [ea, ca], ca.status == "discovered")

        "all" ->
          base_query

        _ ->
          base_query
      end

    Repo.all(base_query)
  end

  # Prepares a search query for FTS5 MATCH.
  # Handles basic query sanitization and wildcard support.
  defp prepare_fts_query(query) do
    # Remove special FTS5 characters that could break the query
    sanitized =
      query
      |> String.replace(~r/[^\w\s\-]/, "")
      |> String.trim()

    # Split into tokens and add prefix matching with *
    tokens =
      sanitized
      |> String.split(~r/\s+/)
      |> Enum.filter(&(&1 != ""))
      |> Enum.map(&"#{&1}*")

    # Join with OR for broader matching
    Enum.join(tokens, " OR ")
  end

  @doc """
  Returns execution agent overview rows for the agents table.
  Joins execution agents with chat agents and projects to get complete information.
  Excludes archived agents by default. Pass `include_archived: true` to include archived agents.

  Options:
  - `:limit` - Maximum number of results (default: 20)
  - `:include_archived` - Include archived agents (default: false)
  - `:project_id` - Filter by project ID
  - `:search_query` - FTS5 search query across all searchable fields
  """
  def list_execution_agent_overview_rows(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    include_archived = Keyword.get(opts, :include_archived, false)
    project_id = Keyword.get(opts, :project_id, nil)
    search_query = Keyword.get(opts, :search_query, "")

    query =
      from(ea in ExecutionAgent,
        join: ca in assoc(ea, :chat_agent),
        left_join: p in EyeInTheSkyWeb.Projects.Project,
        on: p.id == ca.project_id,
        order_by: [desc: ea.started_at],
        limit: ^limit,
        select: %{
          session_id: ea.id,
          session_uuid: ea.uuid,
          session_name: ea.name,
          agent_id: ca.id,
          agent_uuid: ca.uuid,
          agent_description: ca.description,
          project_name: p.name,
          started_at: ea.started_at,
          ended_at: ea.ended_at
        }
      )

    query =
      if include_archived do
        query
      else
        where(query, [ea], is_nil(ea.archived_at))
      end

    query =
      if project_id do
        where(query, [ea, ca], ca.project_id == ^project_id)
      else
        query
      end

    # Apply FTS5 search if query provided
    query =
      if search_query != "" do
        fts_query = prepare_fts_query(search_query)

        where(
          query,
          [ea],
          fragment(
            "EXISTS (SELECT 1 FROM sessions_fts WHERE sessions_fts.rowid = ?.rowid AND sessions_fts MATCH ?)",
            ea,
            ^fts_query
          )
        )
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Loads all data for a specific execution agent.
  Returns tasks, commits, logs, notes, context, and metrics.
  """
  def load_execution_agent_data(agent_id) do
    alias EyeInTheSkyWeb.{Tasks, Commits, Logs, Contexts}

    %{
      tasks: Tasks.list_tasks_for_session(agent_id),
      commits: Commits.list_commits_for_session(agent_id),
      logs: Logs.list_logs_for_session(agent_id),
      # TODO: Fix parent_id type mismatch (INTEGER vs TEXT)
      notes: [],
      session_context: Contexts.get_session_context(agent_id),
      # TODO: Add metrics when table exists
      metrics: nil
    }
  end

  @doc """
  Gets counts for all tabs (cheap aggregate queries).
  """
  def get_execution_agent_counts(agent_id) do
    sql = """
    SELECT
      (SELECT COUNT(*) FROM task_sessions WHERE session_id = ?1),
      (SELECT COUNT(*) FROM commits WHERE session_id = ?1),
      (SELECT COUNT(*) FROM logs WHERE session_id = ?1),
      (SELECT COUNT(*) FROM notes WHERE parent_type IN ('session','sessions') AND parent_id = ?1),
      (SELECT COUNT(*) FROM messages WHERE session_id = ?1)
    """

    case Repo.query(sql, [agent_id]) do
      {:ok, %{rows: [[tasks, commits, logs, notes, messages]]}} ->
        %{tasks: tasks, commits: commits, logs: logs, notes: notes, messages: messages}

      _ ->
        %{tasks: 0, commits: 0, logs: 0, notes: 0, messages: 0}
    end
  end

  @doc """
  Lazy load: tasks only
  """
  def load_execution_agent_tasks(agent_id) do
    EyeInTheSkyWeb.Tasks.list_tasks_for_session(agent_id)
  end

  @doc """
  Lazy load: commits only
  """
  def load_execution_agent_commits(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    EyeInTheSkyWeb.Commits.list_commits_for_session(agent_id, limit: limit)
  end

  @doc """
  Lazy load: logs only
  """
  def load_execution_agent_logs(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    EyeInTheSkyWeb.Logs.list_logs_for_session(agent_id, limit: limit)
  end

  @doc """
  Lazy load: context only
  """
  def load_execution_agent_context(agent_id) do
    EyeInTheSkyWeb.Contexts.get_session_context(agent_id)
  end

  @doc """
  Lazy load: notes only
  """
  def load_execution_agent_notes(agent_id) do
    EyeInTheSkyWeb.Notes.list_notes_for_session(agent_id)
  end

  @doc """
  Extracts and validates model information from a nested model object.

  Expects model info in format:
    {
      "provider": "anthropic",
      "name": "claude-3-5-sonnet",
      "version": "20241022"  # optional
    }

  Returns {:ok, model_attrs} or {:error, reason}.
  """
  def extract_model_info(model_data) when is_map(model_data) do
    with provider when is_binary(provider) <- model_data["provider"] || model_data[:provider],
         name when is_binary(name) <- model_data["name"] || model_data[:name] do
      version = model_data["version"] || model_data[:version]

      {:ok,
       %{
         model_provider: provider,
         model_name: name,
         model_version: version
       }}
    else
      nil -> {:error, "Missing required model fields: provider and name"}
      _ -> {:error, "Invalid model data structure"}
    end
  end

  def extract_model_info(nil) do
    {:error, "Model information required"}
  end

  def extract_model_info(_) do
    {:error, "Model must be a map"}
  end

  @doc """
  Gets model information for an execution agent as a formatted string.

  Returns "provider/name (version)" or "provider/name" if version not set.
  """
  def format_model_info(%ExecutionAgent{} = agent) do
    raw =
      case {agent.model_provider, agent.model_name, agent.model_version} do
        {_provider, name, version}
        when is_binary(name) and is_binary(version) and name != "" and version != "" ->
          "#{name} (#{version})"

        {_provider, name, _} when is_binary(name) and name != "" ->
          name

        _ ->
          # Fall back to provider/model fields
          case {agent.provider, agent.model} do
            {_, m} when is_binary(m) and m != "" -> m
            {p, _} when is_binary(p) and p != "" -> p
            _ -> "unknown"
          end
      end

    # Strip "claude-" prefix for cleaner display (e.g. "claude-opus-4-6" -> "opus-4-6")
    raw
    |> String.replace(~r/^claude-/, "")
    |> String.replace(~r/^claude\//, "")
  end

  def format_model_info(_), do: "unknown"
end
