defmodule EyeInTheSky.Sessions do
  @moduledoc """
  The Sessions context for managing autonomous execution units.

  A Session represents an autonomous Claude process doing work (execution context).
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Sessions.Session

  import Ecto.Query, warn: false

  require Logger

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
  Returns idle or waiting sessions that have not been archived and whose
  last activity (or started_at as fallback) is older than the given cutoff.
  Used by the scheduler to auto-archive dead idle sessions.
  """
  def list_idle_sessions_older_than(cutoff) do
    from(s in Session,
      where: s.status in ["idle", "waiting"],
      where: is_nil(s.archived_at),
      where: not is_nil(s.started_at),
      where: fragment("coalesce(?, ?) < ?", s.last_activity_at, s.started_at, ^cutoff)
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

  @doc """
  Gets a single session, returning {:ok, session} or {:error, :not_found}.
  """
  @spec get_session(integer()) :: {:ok, Session.t()} | {:error, :not_found}
  def get_session(id), do: get(id)

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
    attrs = %{ended_at: DateTime.utc_now()}
    attrs = if s = opts[:summary], do: Map.put(attrs, :description, s), else: attrs
    attrs = if s = opts[:final_status], do: Map.put(attrs, :status, s), else: attrs
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
  Lists active sessions for a specific project, with :agent preloaded.
  Excludes ended and archived sessions.
  """
  def list_active_sessions_for_project(project_id) do
    Session
    |> where([s], s.project_id == ^project_id and is_nil(s.ended_at))
    |> order_by([s], desc: s.started_at)
    |> Archivable.include_archived([])
    |> preload(:agent)
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
      project_sessions_base_query(project_id)
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

  # Deterministic UUIDs for the web UI identity — stable across restarts.
  @web_agent_uuid "00000000-0000-0000-0000-000000000001"
  @web_session_uuid "00000000-0000-0000-0000-000000000002"

  @doc """
  Finds or creates the deterministic web UI session used by ChatLive.
  Returns the integer session ID.

  Safe to call on every mount — returns the existing session immediately
  if it was already bootstrapped.
  """
  @spec ensure_web_ui_session() :: integer()
  def ensure_web_ui_session do
    case get_session_by_uuid(@web_session_uuid) do
      {:ok, session} ->
        session.id

      {:error, :not_found} ->
        with {:ok, agent} <- find_or_create_web_agent(),
             {:ok, session} <-
               create_session(%{
                 uuid: @web_session_uuid,
                 agent_id: agent.id,
                 name: "Web UI",
                 started_at: DateTime.utc_now()
               }) do
          session.id
        else
          {:error, reason} ->
            raise "ensure_web_ui_session bootstrap failed: #{inspect(reason)}"
        end
    end
  end

  defp find_or_create_web_agent do
    case EyeInTheSky.Agents.get_agent_by_uuid(@web_agent_uuid) do
      {:ok, agent} ->
        {:ok, agent}

      {:error, :not_found} ->
        EyeInTheSky.Agents.create_agent(%{
          uuid: @web_agent_uuid,
          description: "Web UI User",
          source: "web"
        })
    end
  end

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
          entrypoint: params["entrypoint"]
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

  defp project_sessions_base_query(project_id) do
    from(s in Session, where: s.project_id == ^project_id)
  end
end
