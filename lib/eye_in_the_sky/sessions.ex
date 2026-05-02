defmodule EyeInTheSky.Sessions do
  @moduledoc """
  The Sessions context for managing autonomous execution units.

  A Session represents an autonomous Claude process doing work (execution context).
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Sessions.Session

  import Ecto.Query, warn: false

  require Logger

  alias EyeInTheSky.Events
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Scopes.Archivable
  alias EyeInTheSky.Sessions.Loader
  alias EyeInTheSky.Sessions.ModelInfo
  alias EyeInTheSky.Sessions.Queries
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
  def get_session(id), do: get(id)

  @doc "Fetch a single session with agent and agent_definition preloaded."
  @spec get_session_with_agent(integer()) :: Session.t() | nil
  def get_session_with_agent(id) do
    Session
    |> where([s], s.id == ^id)
    |> preload(agent: :agent_definition)
    |> Repo.one()
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
  Broadcasts agent_stopped and session_updated events.
  """
  def end_session(%Session{} = session, opts \\ %{}) do
    attrs = %{ended_at: DateTime.utc_now()}
    attrs = if s = opts[:summary], do: Map.put(attrs, :description, s), else: attrs
    attrs = if s = opts[:final_status], do: Map.put(attrs, :status, s), else: attrs

    with {:ok, updated} <- update_session(session, attrs) do
      Events.agent_stopped(updated)
      Events.session_updated(updated)
      {:ok, updated}
    end
  end

  @doc """
  Archives a session (soft delete).
  Broadcasts session_updated event.
  """
  def archive_session(%Session{} = session) do
    with {:ok, updated} <- update_session(session, %{archived_at: DateTime.utc_now()}) do
      Events.session_updated(updated)
      {:ok, updated}
    end
  end

  @doc """
  Unarchives a session.
  Broadcasts session_updated event.
  """
  def unarchive_session(%Session{} = session) do
    with {:ok, updated} <- update_session(session, %{archived_at: nil}) do
      Events.session_updated(updated)
      {:ok, updated}
    end
  end

  @doc """
  Deletes a session (hard delete).
  """
  def delete_session(%Session{} = session), do: delete(session)

  @doc """
  Atomically increments the cached token and cost totals on a session row.

  Called after each message insert that carries usage metadata. Uses a raw
  SQL UPDATE so the increment is a single round-trip with no read-modify-write
  race. When `session_id` is nil or either delta is zero, this is a no-op.
  """
  @spec increment_usage_cache(integer() | nil, non_neg_integer(), float()) :: :ok
  def increment_usage_cache(nil, _tokens, _cost), do: :ok

  def increment_usage_cache(session_id, tokens, cost) do
    Repo.update_all(
      from(s in Session, where: s.id == ^session_id),
      inc: [total_tokens: tokens, total_cost_usd: cost]
    )

    :ok
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session changes.
  """
  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
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
    limit_val = Keyword.get(opts, :limit)
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
  """
  def count_and_ids_for_project(project_id) do
    rows =
      project_sessions_base_query(project_id)
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

  defdelegate list_sessions_filtered(opts \\ []), to: Queries
  defdelegate list_session_overview_rows(opts \\ []), to: Queries
  defdelegate get_session_overview_row(session_id), to: Queries
  defdelegate count_session_overview_rows(opts \\ []), to: Queries

  defdelegate load_session_data(session_id, opts \\ []), to: Loader
  defdelegate get_session_counts(session_id), to: Loader

  @doc """
  Returns statuses that indicate a session can no longer send or receive messages.
  """
  def terminated_statuses, do: ~w(completed failed)

  @doc """
  Broadcasts session_updated event (no DB change).
  """
  def broadcast_session_updated(session), do: Events.session_updated(session)

  @doc """
  Broadcasts session_completed and session_updated events (no DB change).
  """
  def broadcast_session_completed(session) do
    Events.session_completed(session)
    Events.session_updated(session)
  end

  @doc """
  Broadcasts agent_stopped and session_updated events (no DB change).
  """
  def broadcast_session_waiting(session) do
    Events.agent_stopped(session)
    Events.session_updated(session)
  end

  @doc """
  Broadcasts appropriate side-effect events based on status change (no DB change).
  Fires agent_stopped or agent_working depending on status, then session_updated.
  """
  def broadcast_status_side_effects(session, status) do
    if status do
      if status in ["completed", "failed", "waiting", "idle"] do
        Events.agent_stopped(session)
      else
        Events.agent_working(session)
      end
    end

    Events.session_updated(session)
  end

  @doc """
  Extracts and validates model information from a nested model object.

  Delegates to ModelInfo.extract_model_info/1.
  """
  defdelegate extract_model_info(model_data), to: ModelInfo

  # Preload helpers
  defp with_agent_preload(query) do
    preload(query, agent: :agent_definition)
  end

  @doc """
  Gets model information for a session as a formatted string.

  Delegates to ModelInfo.format_model_info/1.
  Returns "provider/name (version)" or "provider/name" if version not set.
  """
  defdelegate format_model_info(session), to: ModelInfo

  defdelegate ensure_web_ui_session(), to: EyeInTheSky.Sessions.WebUiBootstrap

  @doc """
  Registers a new session from a SessionStart hook.

  Takes the raw hook params map and an already-resolved project_id.
  Finds or creates the agent, parses model info, then creates the session.
  Fires `EyeInTheSky.Events.session_started/1` on success.

  Returns `{:ok, %{session: session, agent: agent}}` or `{:error, changeset}`.
  """
  @spec register_from_hook(map(), integer() | nil) ::
          {:ok, %{session: Session.t(), agent: struct()}}
          | {:error, :agent | :session, Ecto.Changeset.t()}
  def register_from_hook(params, project_id) do
    session_uuid = params["session_id"]

    agent_attrs = %{
      uuid: params["agent_id"] || session_uuid,
      description: params["agent_description"] || params["description"],
      project_id: project_id,
      project_name: params["project_name"],
      git_worktree_path: params["worktree_path"],
      source: "hook"
    }

    case EyeInTheSky.Agents.find_or_create_agent(agent_attrs) do
      {:ok, agent} ->
        {model_provider, model_name} = ModelInfo.parse_model_string(params["model"])

        session_attrs = %{
          uuid: session_uuid,
          agent_id: agent.id,
          name: params["name"],
          description: params["description"],
          status: "working",
          started_at: DateTime.utc_now(),
          provider: params["provider"] || "claude",
          model: params["model"],
          model_provider: model_provider,
          model_name: model_name,
          project_id: project_id,
          git_worktree_path: params["worktree_path"],
          entrypoint: params["entrypoint"],
          read_only: params["read_only"] == true or params["read_only"] == "true"
        }

        result =
          if model_name,
            do: create_session_with_model(session_attrs),
            else: create_session(session_attrs)

        case result do
          {:ok, session} ->
            EyeInTheSky.Events.session_started(session)
            {:ok, %{session: session, agent: agent}}

          {:error, changeset} ->
            {:error, :session, changeset}
        end

      {:error, changeset} ->
        {:error, :agent, changeset}
    end
  end

  defdelegate record_tool_event(session, type, params),
    to: EyeInTheSky.Sessions.ToolEventRecorder

  # --- Scope-aware queries ---

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
    limit_val = Keyword.get(opts, :limit)
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

  defp project_sessions_base_query(project_id) do
    from(s in Session, where: s.project_id == ^project_id)
  end
end
