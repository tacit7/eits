defmodule EyeInTheSky.Sessions do
  @moduledoc """
  The Sessions context for managing autonomous execution units.

  A Session represents an autonomous Claude process doing work (execution context).
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Sessions.Session

  import Ecto.Query, warn: false

  require Logger

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Sessions.ModelInfo
  alias EyeInTheSky.Tasks.WorkflowState
  alias EyeInTheSky.Scopes.Archivable
  alias EyeInTheSky.QueryBuilder
  alias EyeInTheSky.Search.PgSearch

  @doc """
  Returns the list of sessions, excluding archived by default.
  Pass `include_archived: true` to include archived sessions.
  """
  @spec list_sessions(keyword()) :: [Session.t()]
  def list_sessions(opts \\ []) do
    Session
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Returns the list of sessions for a specific agent, excluding archived by default.
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
  @spec get_session!(integer()) :: Session.t()
  def get_session!(id), do: get!(id)

  @doc """
  Gets a single session by UUID.

  Raises `Ecto.NoResultsError` if the Session does not exist.
  """
  @spec get_session_by_uuid!(String.t()) :: Session.t()
  def get_session_by_uuid!(uuid), do: get_by_uuid!(uuid)

  @doc """
  Gets a single session by UUID, returning {:ok, session} or {:error, :not_found}.
  """
  @spec get_session_by_uuid(String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def get_session_by_uuid(uuid), do: get_by_uuid(uuid)

  @doc """
  Gets a single session, returning {:ok, session} or {:error, :not_found}.
  """
  @spec get_session(integer()) :: {:ok, Session.t()} | {:error, :not_found}
  def get_session(id), do: get(id)

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
  @spec create_session(map()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def create_session(attrs \\ %{}), do: create(attrs)

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
  @spec update_session(Session.t(), map()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
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
  def end_session(%Session{} = session, opts \\ %{}) do
    attrs =
      %{ended_at: DateTime.utc_now()}
      |> then(fn m ->
        if opts[:summary], do: Map.put(m, :description, opts[:summary]), else: m
      end)
      |> then(fn m ->
        if opts[:final_status],
          do: Map.put(m, :status, opts[:final_status]),
          else: m
      end)

    update_session(session, attrs)
  end

  @doc """
  Archives a session (soft delete).
  """
  def archive_session(%Session{} = session) do
    update_session(session, %{archived_at: DateTime.utc_now()})
  end

  @doc """
  Unarchives a session.
  """
  def unarchive_session(%Session{} = session) do
    Logger.info("unarchive_session id=#{session.id} archived_at=#{inspect(session.archived_at)}")
    result = update_session(session, %{archived_at: nil})
    Logger.info("unarchive_session result=#{inspect(result)}")
    result
  end

  @doc """
  Deletes a session (hard delete).
  """
  def delete_session(%Session{} = session), do: delete(session)

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session changes.
  """
  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
  end

  @doc """
  Lists active sessions (not ended and not archived), excluding archived by default.
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
  Returns sessions ordered by most recent first, excluding archived by default.
  Pass `include_archived: true` to include archived sessions.
  """
  def list_sessions_with_agent(opts \\ []) do
    Session
    |> preload(agent: :agent_definition)
    |> order_by([s], desc: s.started_at)
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Lists sessions for a single project with agents preloaded.
  Returns sessions ordered by most recent first, excluding archived by default.
  Options:
  - `include_archived: true` — include archived sessions
  - `active_only: true` — only sessions where ended_at IS NULL
  - `limit: n` — cap result count at the DB level
  """
  def list_project_sessions_with_agent(project_id, opts \\ []) do
    limit_val = Keyword.get(opts, :limit)
    active_only = Keyword.get(opts, :active_only, false)

    query =
      Session
      |> where([s], s.project_id == ^project_id)
      |> preload(agent: :agent_definition)
      |> order_by([s], desc: s.started_at)
      |> Archivable.include_archived(opts)

    query = if active_only, do: where(query, [s], is_nil(s.ended_at)), else: query
    query = if limit_val, do: limit(query, ^limit_val), else: query

    sessions = Repo.all(query)
    attach_current_task_titles(sessions)
  end

  @doc """
  Returns `{count, [id]}` for all sessions belonging to a project (including archived).
  Lightweight — no preloads, no task title joins.
  """
  def count_and_ids_for_project(project_id) do
    rows =
      Session
      |> where([s], s.project_id == ^project_id)
      |> select([s], s.id)
      |> Repo.all()

    {length(rows), rows}
  end

  defp attach_current_task_titles([]), do: []

  defp attach_current_task_titles(sessions) do
    session_ids = Enum.map(sessions, & &1.id)

    tasks_by_session =
      from(t in EyeInTheSky.Tasks.Task,
        join: ts in "task_sessions",
        on: ts.task_id == t.id,
        where:
          ts.session_id in ^session_ids and t.state_id == ^WorkflowState.in_progress_id() and
            t.archived == false,
        select: {ts.session_id, t.title}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(sessions, fn s ->
      %{s | current_task_title: Map.get(tasks_by_session, s.id)}
    end)
  end

  @doc """
  Lists sessions filtered by search query and status filter using PostgreSQL full-text search.
  Excludes archived sessions by default. Pass `include_archived: true` to include archived sessions.

  Options:
  - `:search_query` - String to search across session name, description, project name, agent ID, agent description
  - `:status_filter` - One of: "all", "active", "completed", "stale", "discovered"
  - `:limit` - Maximum number of results (default: 100)
  - `:offset` - Number of results to skip (default: 0)
  - `:include_archived` - Include archived sessions (default: false)
  """
  def list_sessions_filtered(opts \\ []) do
    search_query = Keyword.get(opts, :search_query, "")
    status_filter = Keyword.get(opts, :status_filter, "active")
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    project_id = Keyword.get(opts, :project_id, nil)

    base_query =
      from s in Session,
        join: a in assoc(s, :agent),
        left_join: ad in assoc(a, :agent_definition),
        preload: [agent: {a, agent_definition: ad}],
        order_by: [desc_nulls_last: s.last_activity_at, desc: s.started_at],
        limit: ^limit,
        offset: ^offset

    base_query = Archivable.include_archived(base_query, opts)

    # Apply project filter
    base_query =
      if project_id do
        where(base_query, [s, a], s.project_id == ^project_id or a.project_id == ^project_id)
      else
        base_query
      end

    # Apply full-text search filter
    base_query =
      if search_query != "" do
        where(base_query, [s, a], ^PgSearch.fts_name_description_match(search_query))
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
  Returns session overview rows for the sessions table.
  Joins sessions with agents and projects to get complete information.
  Excludes archived sessions by default. Pass `include_archived: true` to include archived sessions.

  Options:
  - `:limit` - Maximum number of results (default: 20)
  - `:include_archived` - Include archived sessions (default: false)
  - `:project_id` - Filter by project ID
  - `:search_query` - PostgreSQL full-text search query across all searchable fields
  """
  def list_session_overview_rows(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    base_session_overview_query(opts)
    |> order_by([s], desc: s.started_at)
    |> limit(^limit)
    |> QueryBuilder.maybe_offset(opts)
    |> select([s, a, p], %{
      id: s.id,
      uuid: s.uuid,
      name: s.name,
      agent_id: a.id,
      agent_uuid: a.uuid,
      description: s.description,
      project_name: p.name,
      started_at: s.started_at,
      ended_at: s.ended_at,
      status: s.status,
      intent: s.intent,
      model_provider: s.model_provider,
      model_name: s.model_name,
      model_version: s.model_version,
      last_activity_at: a.last_activity_at,
      current_task_title:
        fragment(
          # 2 = WorkflowState.in_progress_id()
          "(SELECT t.title FROM tasks t JOIN task_sessions ts ON ts.task_id = t.id WHERE ts.session_id = ? AND t.state_id = 2 AND t.archived = false ORDER BY t.updated_at DESC LIMIT 1)",
          s.id
        )
    })
    |> Repo.all()
  end

  @doc "Fetch a single session in the overview row format (same shape as list_session_overview_rows)."
  def get_session_overview_row(session_id) do
    from(s in Session,
      join: a in assoc(s, :agent),
      left_join: p in EyeInTheSky.Projects.Project,
      on: p.id == a.project_id,
      where: s.id == ^session_id and is_nil(s.archived_at),
      select: %{
        id: s.id,
        uuid: s.uuid,
        name: s.name,
        agent_id: a.id,
        agent_uuid: a.uuid,
        description: s.description,
        project_name: p.name,
        started_at: s.started_at,
        ended_at: s.ended_at,
        status: s.status,
        intent: s.intent,
        model_provider: s.model_provider,
        model_name: s.model_name,
        model_version: s.model_version,
        last_activity_at: a.last_activity_at,
        current_task_title:
          fragment(
            "(SELECT t.title FROM tasks t JOIN task_sessions ts ON ts.task_id = t.id WHERE ts.session_id = ? AND t.state_id = 2 AND t.archived = false ORDER BY t.updated_at DESC LIMIT 1)",
            s.id
          )
      }
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      row -> {:ok, row}
    end
  end

  @doc """
  Counts sessions for overview (same filters as list_session_overview_rows, without limit/offset).
  """
  def count_session_overview_rows(opts \\ []) do
    base_session_overview_query(opts)
    |> Repo.aggregate(:count, :id)
  end

  defp base_session_overview_query(opts) do
    project_id = Keyword.get(opts, :project_id, nil)
    search_query = Keyword.get(opts, :search_query, "")

    query =
      from(s in Session,
        join: a in assoc(s, :agent),
        left_join: p in EyeInTheSky.Projects.Project,
        on: p.id == a.project_id
      )

    query = Archivable.include_archived(query, opts)
    query = if project_id, do: where(query, [s, a], a.project_id == ^project_id), else: query

    if search_query != "" do
      where(query, [s], ^PgSearch.fts_name_description_match(search_query))
    else
      query
    end
  end

  @doc """
  Loads associated data for a specific session detail view.

  Intended for single-session detail pages only. Do NOT use for list views
  or anywhere multiple sessions are rendered — it issues one query per
  association.

  ## Options

    - `:tasks_limit` / `:tasks_offset` — paginate tasks
    - `:commits_limit` / `:commits_offset` — paginate commits
    - `:logs_limit` / `:logs_offset` — paginate logs
    - `:notes_limit` / `:notes_offset` — paginate notes

  ## Examples

      iex> load_session_data("abc-123")
      %{tasks: [...], commits: [...], ...}

      iex> load_session_data("abc-123", tasks_limit: 20, logs_limit: 50, logs_offset: 50)
      %{tasks: [...], ...}

  """
  def load_session_data(session_id, opts \\ []) do
    alias EyeInTheSky.{Tasks, Commits, Logs, Contexts, Notes}

    %{
      tasks:
        Tasks.list_tasks_for_session(session_id,
          limit: Keyword.get(opts, :tasks_limit),
          offset: Keyword.get(opts, :tasks_offset)
        ),
      commits:
        Commits.list_commits_for_session(session_id,
          limit: Keyword.get(opts, :commits_limit),
          offset: Keyword.get(opts, :commits_offset)
        ),
      logs:
        Logs.list_logs_for_session(session_id,
          limit: Keyword.get(opts, :logs_limit),
          offset: Keyword.get(opts, :logs_offset)
        ),
      notes:
        Notes.list_notes_for_session(session_id,
          limit: Keyword.get(opts, :notes_limit),
          offset: Keyword.get(opts, :notes_offset)
        ),
      session_context: Contexts.get_session_context(session_id),
      metrics: nil
    }
  end

  @doc """
  Gets counts for all tabs (cheap aggregate queries).
  """
  def get_session_counts(session_id) do
    sql = """
    SELECT
      (SELECT COUNT(*) FROM task_sessions WHERE session_id = $1),
      (SELECT COUNT(*) FROM commits WHERE session_id = $1),
      (SELECT COUNT(*) FROM logs WHERE session_id = $1),
      (SELECT COUNT(*) FROM notes WHERE parent_type IN ('session','sessions') AND parent_id = $1),
      (SELECT COUNT(*) FROM messages WHERE session_id = $1)
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
    EyeInTheSky.Tasks.list_tasks_for_session(session_id)
  end

  @doc """
  Lazy load: commits only
  """
  def load_session_commits(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    EyeInTheSky.Commits.list_commits_for_session(session_id, limit: limit)
  end

  @doc """
  Lazy load: logs only
  """
  def load_session_logs(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    EyeInTheSky.Logs.list_logs_for_session(session_id, limit: limit)
  end

  @doc """
  Lazy load: context only
  """
  def load_session_context(session_id) do
    EyeInTheSky.Contexts.get_session_context(session_id)
  end

  @doc """
  Lazy load: notes only
  """
  def load_session_notes(session_id) do
    EyeInTheSky.Notes.list_notes_for_session(session_id)
  end

  @doc """
  Extracts and validates model information from a nested model object.

  Delegates to ModelInfo.extract_model_info/1.
  """
  defdelegate extract_model_info(model_data), to: ModelInfo

  @doc """
  Gets model information for a session as a formatted string.

  Delegates to ModelInfo.format_model_info/1.
  Returns "provider/name (version)" or "provider/name" if version not set.
  """
  defdelegate format_model_info(session), to: ModelInfo
end
