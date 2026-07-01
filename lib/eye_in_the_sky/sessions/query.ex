defmodule EyeInTheSky.Sessions.Query do
  @moduledoc """
  Query and retrieval functions for sessions.

  Handles reading sessions by various criteria without modifying state.
  """

  import Ecto.Query, warn: false

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Scopes.Archivable
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Tasks.WorkflowState
  alias EyeInTheSky.Utils.ToolHelpers

  @doc """
  Returns the list of sessions, excluding archived by default.
  Pass `include_archived: true` to include archived sessions.
  Pass `limit: n` to cap results (default: 1_000).
  """
  @spec list_sessions(keyword()) :: [Session.t()]
  def list_sessions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 1_000)

    Session
    |> Archivable.include_archived(opts)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns the list of sessions for a specific agent, excluding archived by default.
  Pass `include_archived: true` to include archived sessions.
  Pass `limit: n` to cap results (default: 200).
  """
  def list_sessions_for_agent(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    Session
    |> where([s], s.agent_id == ^agent_id)
    |> order_by([s], desc: s.started_at)
    |> limit(^limit)
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Returns sessions with IDs in the given list. Returns [] for an empty list.
  """
  def list_sessions_by_ids([]), do: []

  def list_sessions_by_ids(ids) do
    Repo.all(from s in Session, where: s.id in ^ids)
  end

  @doc """
  Returns sessions matching mixed ID types (integers or UUIDs).

  Splits ids into integer and UUID lists, then queries by both.
  Returns [] for an empty list or when no sessions are found.
  """
  def list_sessions_by_mixed_ids([]), do: []

  def list_sessions_by_mixed_ids(ids) when is_list(ids) do
    int_ids =
      ids
      |> Enum.flat_map(fn
        id when is_integer(id) ->
          [id]

        s when is_binary(s) ->
          case Integer.parse(s) do
            {n, ""} -> [n]
            _ -> []
          end

        _ ->
          []
      end)

    uuid_ids =
      ids
      |> Enum.filter(fn
        id when is_integer(id) ->
          false

        s when is_binary(s) ->
          case Ecto.UUID.cast(s) do
            {:ok, _} -> true
            _ -> false
          end

        _ ->
          false
      end)

    case {int_ids, uuid_ids} do
      {[], []} ->
        []

      {[], uuids} ->
        Repo.all(from s in Session, where: s.uuid in ^uuids, limit: 100)

      {ints, []} ->
        Repo.all(from s in Session, where: s.id in ^ints, limit: 100)

      {ints, uuids} ->
        Repo.all(from s in Session, where: s.id in ^ints or s.uuid in ^uuids, limit: 100)
    end
  end

  @doc """
  Returns a map of %{agent_id => most_recent_session_id} for a list of agent IDs.
  Used for @mention autocomplete — resolves the latest session per agent in one query.
  """
  def latest_session_id_by_agents([]), do: %{}

  def latest_session_id_by_agents(agent_ids) when is_list(agent_ids) do
    from(s in Session,
      where: s.agent_id in ^agent_ids,
      group_by: s.agent_id,
      select: {s.agent_id, max(s.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns idle or waiting sessions that have not been archived and whose
  last activity (or started_at as fallback) is older than the given cutoff.
  Used by the scheduler to auto-archive dead idle sessions.
  """
  def list_idle_sessions_older_than(cutoff) do
    # Two OR branches so PG can use the sessions(:last_activity_at) and
    # sessions(:started_at) indexes added in 20260501053649. A single
    # coalesce(last_activity_at, started_at) expression prevents index use.
    from(s in Session,
      where: s.status in ["idle", "waiting"],
      where: is_nil(s.archived_at),
      where: not is_nil(s.started_at),
      where:
        (not is_nil(s.last_activity_at) and s.last_activity_at < ^cutoff) or
          (is_nil(s.last_activity_at) and s.started_at < ^cutoff)
    )
    |> Repo.all()
  end

  @doc """
  Gets a single session.

  Raises `Ecto.NoResultsError` if the Session does not exist.
  """
  @spec get_session!(integer()) :: Session.t()
  def get_session!(id), do: Repo.get!(Session, id)

  @doc """
  Gets a single session by UUID.

  Raises `Ecto.NoResultsError` if the Session does not exist.
  """
  @spec get_session_by_uuid!(String.t()) :: Session.t()
  def get_session_by_uuid!(uuid) do
    Repo.get_by!(Session, uuid: uuid)
  end

  @doc """
  Gets a single session by UUID, returning {:ok, session} or {:error, :not_found}.
  """
  @spec get_session_by_uuid(String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def get_session_by_uuid(uuid) when is_binary(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, _} ->
        case Repo.get_by(Session, uuid: uuid) do
          nil -> {:error, :not_found}
          session -> {:ok, session}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc "Returns {:ok, id} if a session with the given UUID exists, else :error."
  @spec get_session_id_by_uuid(String.t()) :: {:ok, integer()} | :error
  def get_session_id_by_uuid(uuid) when is_binary(uuid) do
    case Ecto.UUID.dump(uuid) do
      {:ok, bin} ->
        case Repo.query("SELECT id FROM sessions WHERE uuid = $1 LIMIT 1", [bin]) do
          {:ok, %{rows: [[id]]}} -> {:ok, id}
          {:ok, %{rows: []}} -> :error
          _ -> :error
        end

      _ ->
        :error
    end
  end

  @doc """
  Gets a single session, returning {:ok, session} or {:error, :not_found}.
  """
  @spec get_session(integer()) :: {:ok, Session.t()} | {:error, :not_found}
  def get_session(id) do
    case Repo.get(Session, id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  @doc "Fetch a single session with agent and agent_definition preloaded."
  @spec get_session_with_agent(integer()) :: Session.t() | nil
  def get_session_with_agent(id) do
    Session
    |> where([s], s.id == ^id)
    |> preload(agent: :agent_definition)
    |> Repo.one()
  end

  @doc """
  Return the agent definition slug (agent type) for a session identified by its UUID.

  Used by the IAM hook controller to enrich the hook payload with the agent type
  before policy evaluation. A single three-table join avoids loading the full session
  struct when only the slug is needed.

  Returns `{:ok, slug}` when found, `:error` when the session, agent, or agent
  definition is missing.
  """
  @spec agent_type_for_session(String.t()) :: {:ok, String.t()} | :error
  def agent_type_for_session(uuid) when is_binary(uuid) do
    result =
      from(s in Session,
        join: a in assoc(s, :agent),
        join: ad in assoc(a, :agent_definition),
        where: s.uuid == ^uuid,
        select: ad.slug,
        limit: 1
      )
      |> Repo.one()

    case result do
      nil -> :error
      slug -> {:ok, slug}
    end
  end

  @doc """
  Resolves a session from an integer ID or UUID string.
  Returns {:ok, session} or {:error, :not_found}.
  """
  @spec resolve(integer() | String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def resolve(id) when is_integer(id), do: get_session(id)

  def resolve(ref) when is_binary(ref) do
    if id = ToolHelpers.parse_int(ref), do: get_session(id), else: get_session_by_uuid(ref)
  end

  @doc """
  Lists active sessions (not ended and not archived), excluding archived by default.
  Pass `include_archived: true` to include archived sessions.
  Pass `limit: n` to cap results (default: 500).
  """
  def list_active_sessions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    Session
    |> where([s], is_nil(s.ended_at))
    |> order_by([s], desc: s.started_at)
    |> limit(^limit)
    |> Archivable.include_archived(opts)
    |> Repo.all()
  end

  @doc """
  Lists active sessions for a specific project, with :agent preloaded.
  Excludes ended and archived sessions.
  Pass `limit: n` to cap results (default: 500).
  """
  def list_active_sessions_for_project(project_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    Session
    |> where([s], s.project_id == ^project_id and is_nil(s.ended_at))
    |> order_by([s], desc: s.started_at)
    |> limit(^limit)
    |> Archivable.include_archived([])
    |> preload(:agent)
    |> Repo.all()
  end

  @doc """
  Lists all sessions with agent preloaded for the overview page.
  Returns sessions ordered by most recent first, excluding archived by default.
  Pass `include_archived: true` to include archived sessions.
  Pass `limit: n` to cap results (default: 500).
  """
  def list_sessions_with_agent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    Session
    |> with_agent_preload()
    |> order_by([s], desc: s.started_at)
    |> limit(^limit)
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
    limit_val = Keyword.get(opts, :limit, 500)
    offset_val = Keyword.get(opts, :offset)
    active_only = Keyword.get(opts, :active_only, false)

    query =
      project_sessions_base_query(project_id)
      |> with_agent_preload()
      |> order_by([s], desc: s.started_at)
      |> Archivable.include_archived(opts)

    query = if active_only, do: where(query, [s], is_nil(s.ended_at)), else: query
    query = if offset_val, do: offset(query, ^offset_val), else: query
    query = if limit_val, do: limit(query, ^limit_val), else: query

    sessions = Repo.all(query)
    attach_current_task_titles(sessions)
  end

  @doc """
  Returns `{count, [id]}` for all sessions belonging to a project (including archived).
  Lightweight — no preloads, no task title joins.
  Returns up to 10000 IDs to avoid unbounded memory usage.
  """
  def count_and_ids_for_project(project_id) do
    base_query = project_sessions_base_query(project_id)

    # Get true count via COUNT(*)
    count_query = base_query |> select([s], count(s.id))
    count = Repo.one(count_query)

    # Get IDs (limited to 10000 to avoid OOM)
    ids_query = base_query |> select([s], s.id) |> limit(10_000)
    ids = Repo.all(ids_query)

    {count, ids}
  end

  @doc """
  Lists sessions for a given `EyeInTheSky.Scope`.

  - Project scope: returns sessions for that project, ordered by started_at desc.
  - Workspace scope: returns sessions across all projects in the workspace,
    preloads :project so callers can show the project label.

  Accepts the same opts as `list_project_sessions_with_agent/2`:
  `include_archived`, `active_only`, `limit`.
  """
  def list_sessions_for_scope(scope, opts \\ [])

  def list_sessions_for_scope(%EyeInTheSky.Scope{type: :project, project_id: pid}, opts) do
    list_project_sessions_with_agent(pid, opts)
  end

  def list_sessions_for_scope(%EyeInTheSky.Scope{type: :workspace, workspace_id: wid}, opts) do
    limit_val = Keyword.get(opts, :limit, 500)
    offset_val = Keyword.get(opts, :offset)
    active_only = Keyword.get(opts, :active_only, false)

    query =
      from s in Session,
        join: p in EyeInTheSky.Projects.Project,
        on: s.project_id == p.id and p.workspace_id == ^wid,
        order_by: [desc: s.started_at],
        preload: [project: p]

    query = Archivable.include_archived(query, opts)
    query = if active_only, do: where(query, [s], is_nil(s.ended_at)), else: query
    query = if offset_val, do: offset(query, ^offset_val), else: query
    query = if limit_val, do: limit(query, ^limit_val), else: query

    query
    |> with_agent_preload()
    |> Repo.all()
    |> attach_current_task_titles()
  end

  @doc "Preloads the :project association on a session struct."
  def preload_project(%Session{} = session), do: Repo.preload(session, :project)

  # --- Private Helpers ---

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

  defp with_agent_preload(query) do
    preload(query, agent: :agent_definition)
  end

  defp project_sessions_base_query(project_id) do
    from(s in Session, where: s.project_id == ^project_id)
  end
end
