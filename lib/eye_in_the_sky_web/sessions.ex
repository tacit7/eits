defmodule EyeInTheSkyWeb.Sessions do
  @moduledoc """
  The Sessions context for managing agent sessions.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Sessions.Session
  alias EyeInTheSkyWeb.Scopes.Archivable

  @doc """
  Returns the list of sessions, excluding archived sessions by default.
  Pass `include_archived: true` to include archived sessions.
  """
  def list_sessions(opts \\ []) do
    Session
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Returns the list of sessions for a specific agent, excluding archived sessions by default.
  Pass `include_archived: true` to include archived sessions.
  """
  def list_sessions_for_agent(agent_id, opts \\ []) do
    Session
    |> where([s], s.agent_id == ^agent_id)
    |> order_by([s], desc: s.started_at)
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Gets a single session.

  Raises `Ecto.NoResultsError` if the Session does not exist.
  """
  def get_session!(id) do
    Repo.get!(Session, id)
  end

  @doc """
  Gets a single session by UUID.

  Raises `Ecto.NoResultsError` if the Session does not exist.
  """
  def get_session_by_uuid!(uuid) do
    Repo.get_by!(Session, uuid: uuid)
  end

  @doc """
  Gets a single session by UUID, returning {:ok, session} or {:error, :not_found}.

  This is the safe version that doesn't raise exceptions.
  """
  def get_session_by_uuid(uuid) do
    case Repo.get_by(Session, uuid: uuid) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  @doc """
  Gets a single session, returning {:ok, session} or {:error, :not_found}.

  This is the safe version that doesn't raise exceptions.
  """
  def get_session(id) do
    case Repo.get(Session, id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  @doc """
  Gets a single session with logs preloaded.
  """
  def get_session_with_logs!(id) do
    Session
    |> preload(:logs)
    |> Repo.get!(id)
  end

  @doc """
  Creates a session.
  """
  def create_session(attrs \\ %{}) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a session with model tracking information.

  Requires model_provider and model_name in attrs.
  Model info is immutable after creation.

  Returns {:ok, session} or {:error, changeset}.
  """
  def create_session_with_model(attrs \\ %{}) do
    %Session{}
    |> Session.creation_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a session, but prevents modification of model fields.

  Model information is immutable per session.
  Attempting to change model_provider or model_name will be ignored.
  """
  def update_session(%Session{} = session, attrs) do
    # Remove model fields if present - they are immutable
    attrs =
      attrs
      |> Map.delete(:model_provider)
      |> Map.delete(:model_name)
      |> Map.delete(:model_version)

    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Ends a session by setting ended_at timestamp.
  """
  def end_session(%Session{} = session) do
    update_session(session, %{ended_at: DateTime.utc_now()})
  end

  @doc """
  Archives a session (soft delete).
  """
  def archive_session(%Session{} = session) do
    now = DateTime.utc_now() |> DateTime.to_string()
    update_session(session, %{archived_at: now})
  end

  @doc """
  Unarchives a session.
  """
  def unarchive_session(%Session{} = session) do
    require Logger
    Logger.info("📦 Unarchiving session #{session.id}, current archived_at: #{inspect(session.archived_at)}")
    result = update_session(session, %{archived_at: nil})
    Logger.info("📦 Update result: #{inspect(result)}")
    result
  end

  @doc """
  Deletes a session (hard delete).
  """
  def delete_session(%Session{} = session) do
    Repo.delete(session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session changes.
  """
  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
  end

  @doc """
  Lists active sessions (not ended and not archived), excluding archived sessions by default.
  Pass `include_archived: true` to include archived sessions.
  """
  def list_active_sessions(opts \\ []) do
    Session
    |> where([s], is_nil(s.ended_at))
    |> order_by([s], desc: s.started_at)
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Lists all sessions with agent preloaded for the overview page.
  Returns sessions ordered by most recent first, excluding archived sessions by default.
  Pass `include_archived: true` to include archived sessions.
  """
  def list_sessions_with_agent(opts \\ []) do
    Session
    |> preload(:agent)
    |> order_by([s], desc: s.started_at)
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Lists sessions filtered by search query and status filter using FTS5 full-text search.
  Only returns active (non-archived) sessions.

  Options:
  - `:search_query` - String to search across session name, description, project name, session ID, agent description
  - `:status_filter` - One of: "all", "active", "completed", "stale", "discovered"
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Number of results to skip (default: 0)
  """
  def list_sessions_filtered(opts \\ []) do
    search_query = Keyword.get(opts, :search_query, "")
    status_filter = Keyword.get(opts, :status_filter, "active")
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    base_query =
      from s in Session,
        join: a in assoc(s, :agent),
        where: is_nil(s.archived_at),
        preload: [agent: a],
        order_by: [desc: s.started_at],
        limit: ^limit,
        offset: ^offset

    # Apply FTS5 search filter
    base_query =
      if search_query != "" do
        # Use FTS5 MATCH query for full-text search
        fts_query = prepare_fts_query(search_query)

        where(
          base_query,
          [s, a],
          fragment(
            "EXISTS (SELECT 1 FROM sessions_fts WHERE sessions_fts.rowid = ?.rowid AND sessions_fts MATCH ?)",
            s,
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
          where(base_query, [s, a], is_nil(s.ended_at) and a.status != "discovered")

        "completed" ->
          where(base_query, [s], not is_nil(s.ended_at))

        "stale" ->
          where(base_query, [s, a], is_nil(s.ended_at) and a.status == "stale")

        "discovered" ->
          where(base_query, [s, a], a.status == "discovered")

        "all" ->
          base_query

        _ ->
          base_query
      end

    Repo.all(base_query)
  end

  @doc """
  Prepares a search query for FTS5 MATCH.
  Handles basic query sanitization and wildcard support.
  """
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
  Returns session overview rows for the sessions table.
  Joins sessions with agents and projects to get complete information.
  Excludes archived sessions by default. Pass `include_archived: true` to include archived sessions.

  Options:
  - `:limit` - Maximum number of results (default: 20)
  - `:include_archived` - Include archived sessions (default: false)
  - `:project_id` - Filter by project ID
  - `:search_query` - FTS5 search query across all searchable fields
  """
  def list_session_overview_rows(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    include_archived = Keyword.get(opts, :include_archived, false)
    project_id = Keyword.get(opts, :project_id, nil)
    search_query = Keyword.get(opts, :search_query, "")

    query =
      from(s in Session,
        join: a in assoc(s, :agent),
        left_join: p in EyeInTheSkyWeb.Projects.Project,
        on: p.id == a.project_id,
        order_by: [desc: s.started_at],
        limit: ^limit,
        select: %{
          session_id: s.id,
          session_uuid: s.uuid,
          session_name: s.name,
          agent_id: a.id,
          agent_uuid: a.uuid,
          agent_description: a.description,
          project_name: p.name,
          started_at: s.started_at,
          ended_at: s.ended_at
        }
      )

    query =
      if include_archived do
        query
      else
        where(query, [s], is_nil(s.archived_at))
      end

    query =
      if project_id do
        where(query, [s, a], a.project_id == ^project_id)
      else
        query
      end

    # Apply FTS5 search if query provided
    query =
      if search_query != "" do
        fts_query = prepare_fts_query(search_query)

        where(
          query,
          [s],
          fragment(
            "EXISTS (SELECT 1 FROM sessions_fts WHERE sessions_fts.rowid = ?.rowid AND sessions_fts MATCH ?)",
            s,
            ^fts_query
          )
        )
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Loads all data for a specific session.
  Returns tasks, commits, logs, notes, context, and metrics.
  """
  def load_session_data(session_id) do
    alias EyeInTheSkyWeb.{Tasks, Commits, Logs, Contexts}

    %{
      tasks: Tasks.list_tasks_for_session(session_id),
      commits: Commits.list_commits_for_session(session_id),
      logs: Logs.list_logs_for_session(session_id),
      # TODO: Fix parent_id type mismatch (INTEGER vs TEXT)
      notes: [],
      session_context: Contexts.get_session_context(session_id),
      # TODO: Add metrics when table exists
      metrics: nil
    }
  end

  @doc """
  Gets counts for all tabs (cheap aggregate queries).
  """
  def get_session_counts(session_id) do
    sql = """
    SELECT
      (SELECT COUNT(*) FROM task_sessions WHERE session_id = ?1),
      (SELECT COUNT(*) FROM commits WHERE session_id = ?1),
      (SELECT COUNT(*) FROM logs WHERE session_id = ?1),
      (SELECT COUNT(*) FROM notes WHERE parent_type IN ('session','sessions') AND parent_id = ?1),
      (SELECT COUNT(*) FROM messages WHERE session_id = ?1)
    """

    case Repo.query(sql, [session_id]) do
      {:ok, %{rows: [[tasks, commits, logs, notes, messages]]}} ->
        %{tasks: tasks, commits: commits, logs: logs, notes: notes, messages: messages}

      _ ->
        %{tasks: 0, commits: 0, logs: 0, notes: 0, messages: 0}
    end
  end

  @doc """
  Lazy load: tasks only
  """
  def load_session_tasks(session_id) do
    EyeInTheSkyWeb.Tasks.list_tasks_for_session(session_id)
  end

  @doc """
  Lazy load: commits only
  """
  def load_session_commits(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    EyeInTheSkyWeb.Commits.list_commits_for_session(session_id, limit: limit)
  end

  @doc """
  Lazy load: logs only
  """
  def load_session_logs(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    EyeInTheSkyWeb.Logs.list_logs_for_session(session_id, limit: limit)
  end

  @doc """
  Lazy load: context only
  """
  def load_session_context(session_id) do
    EyeInTheSkyWeb.Contexts.get_session_context(session_id)
  end

  @doc """
  Lazy load: notes only
  """
  def load_session_notes(session_id) do
    EyeInTheSkyWeb.Notes.list_notes_for_session(session_id)
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
  Gets model information for a session as a formatted string.

  Returns "provider/name (version)" or "provider/name" if version not set.
  """
  def format_model_info(%Session{} = session) do
    raw =
      case {session.model_provider, session.model_name, session.model_version} do
        {_provider, name, version}
        when is_binary(name) and is_binary(version) and name != "" and version != "" ->
          "#{name} (#{version})"

        {_provider, name, _} when is_binary(name) and name != "" ->
          name

        _ ->
          # Fall back to provider/model fields
          case {session.provider, session.model} do
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
