defmodule EyeInTheSky.Sessions do
  @moduledoc """
  The Sessions context for managing autonomous execution units.

  A Session represents an autonomous Claude process doing work (execution context).
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Sessions.Session

  import Ecto.Query, warn: false

  require Logger

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Utils.ToolHelpers
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Sessions.ModelInfo
  alias EyeInTheSky.Tasks.WorkflowState
  alias EyeInTheSky.Scopes.Archivable
  alias EyeInTheSky.Sessions.Queries

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

  defdelegate list_sessions_filtered(opts \\ []), to: Queries
  defdelegate list_session_overview_rows(opts \\ []), to: Queries
  defdelegate get_session_overview_row(session_id), to: Queries
  defdelegate count_session_overview_rows(opts \\ []), to: Queries

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
    alias EyeInTheSky.{Commits, Logs, Notes, Messages}

    tasks =
      from(ts in "task_sessions", where: ts.session_id == ^session_id, select: count())
      |> Repo.one()

    commits =
      from(c in Commits.Commit, where: c.session_id == ^session_id, select: count())
      |> Repo.one()

    logs =
      from(l in Logs.SessionLog, where: l.session_id == ^session_id, select: count())
      |> Repo.one()

    notes =
      from(n in Notes.Note,
        where:
          n.parent_type in ["session", "sessions"] and
            n.parent_id == ^to_string(session_id),
        select: count()
      )
      |> Repo.one()

    messages =
      from(m in Messages.Message, where: m.session_id == ^session_id, select: count())
      |> Repo.one()

    %{tasks: tasks, commits: commits, logs: logs, notes: notes, messages: messages}
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
        agent =
          case EyeInTheSky.Agents.get_agent_by_uuid(@web_agent_uuid) do
            {:ok, a} ->
              a

            {:error, :not_found} ->
              {:ok, a} =
                EyeInTheSky.Agents.create_agent(%{
                  uuid: @web_agent_uuid,
                  description: "Web UI User",
                  source: "web"
                })

              a
          end

        {:ok, session} =
          create_session(%{
            uuid: @web_session_uuid,
            agent_id: agent.id,
            name: "Web UI",
            started_at: DateTime.utc_now()
          })

        session.id
    end
  end

  @doc """
  Records a tool pre/post event, creates a Message record, and fires PubSub events.

  Takes the session, event type ("pre" or "post"), and params containing
  tool_name and tool_input.

  Returns :ok or {:error, reason}.
  """
  def record_tool_event(session, type, params) do
    tool_name = params["tool_name"]
    tool_input = params["tool_input"] || %{}

    case type do
      "pre" ->
        input_json = Jason.encode!(tool_input)
        body = "Tool: #{tool_name}\n#{input_json}" |> String.slice(0..3999)

        EyeInTheSky.Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session.id,
          sender_role: "tool",
          recipient_role: "user",
          direction: "inbound",
          body: body,
          status: "delivered",
          provider: "claude",
          metadata: %{
            "stream_type" => "tool_use",
            "tool_name" => tool_name,
            "input" => tool_input
          }
        })

        EyeInTheSky.Events.agent_working(session)
        EyeInTheSky.Events.session_tool_use(session.id, tool_name, tool_input)
        :ok

      "post" ->
        input_json = Jason.encode!(tool_input)
        body = "Tool: #{tool_name} (completed)\n#{input_json}" |> String.slice(0..3999)

        EyeInTheSky.Messages.create_message(%{
          uuid: Ecto.UUID.generate(),
          session_id: session.id,
          sender_role: "tool",
          recipient_role: "user",
          direction: "inbound",
          body: body,
          status: "delivered",
          provider: "claude",
          metadata: %{"stream_type" => "tool_result", "tool_name" => tool_name}
        })

        EyeInTheSky.Events.session_tool_result(session.id, tool_name, false)
        :ok

      _ ->
        {:error, "Invalid type"}
    end
  end
end
