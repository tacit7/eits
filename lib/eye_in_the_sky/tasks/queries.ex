defmodule EyeInTheSky.Tasks.Queries do
  @moduledoc false

  import Ecto.Query, warn: false

  alias EyeInTheSky.Notes.NoteQueries
  alias EyeInTheSky.QueryBuilder
  alias EyeInTheSky.QueryHelpers
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Search.PgSearch
  alias EyeInTheSky.Tasks.{Task, WorkflowState}

  @full_task_preloads [:state, :tags, :sessions, :checklist_items, :agent]

  @doc """
  Returns the list of tasks.

  Options:
  - `:limit` - maximum number of tasks to return (default: nil = all)
  - `:offset` - number of tasks to skip (default: 0)
  - `:state_id` - filter by workflow state ID (default: nil = all)
  """
  def list_tasks(opts \\ []) do
    sort_by = Keyword.get(opts, :sort_by, "created_desc")

    base_tasks_query(opts)
    |> preload(^@full_task_preloads)
    |> task_order(sort_by)
    |> QueryBuilder.maybe_limit(opts)
    |> QueryBuilder.maybe_offset(opts)
    |> Repo.all()
  end

  @doc """
  Returns the count of tasks matching the given filters.

  Options:
  - `:state_id` - filter by workflow state ID (default: nil = all)
  """
  def count_tasks(opts \\ []) do
    base_tasks_query(opts)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Returns the list of tasks for a specific agent.
  """
  def list_tasks_for_agent(agent_id, opts \\ []) do
    Task
    |> where([t], t.agent_id == ^agent_id)
    |> QueryBuilder.maybe_where(opts, :state_id)
    |> maybe_since(opts)
    |> maybe_stale_since(opts)
    |> preload(^@full_task_preloads)
    |> order_by([t],
      desc: fragment("CASE WHEN ? IS NULL THEN 0 ELSE 1 END", t.archived),
      desc: t.priority,
      asc: t.created_at
    )
    |> QueryBuilder.maybe_limit(opts)
    |> Repo.all()
  end

  @doc """
  Returns the list of tasks for a specific session.
  """
  def list_tasks_for_session(session_id, opts \\ []) do
    tasks =
      Task
      |> join(:inner, [t], ts in "task_sessions", on: ts.task_id == t.id)
      |> where([t, ts], ts.session_id == ^session_id)
      |> QueryBuilder.maybe_where(opts, :state_id)
      |> maybe_since(opts)
      |> maybe_stale_since(opts)
      |> order_by([t], desc: t.priority, asc: t.created_at)
      |> preload([:state, :tags])
      |> QueryBuilder.maybe_limit(opts)
      |> QueryBuilder.maybe_offset(opts)
      |> Repo.all()

    if Keyword.get(opts, :notes_count, true) do
      NoteQueries.with_notes_count(tasks)
    else
      tasks
    end
  end

  @doc """
  Batch-fetches tasks for a list of session integer IDs in a single query.
  Returns a map of %{session_id => [task, ...]} for in-memory grouping.
  No notes_count overhead — intended for lightweight list endpoints.
  """
  def list_tasks_for_sessions(session_ids) when is_list(session_ids) do
    if session_ids == [] do
      %{}
    else
      rows =
        from(t in Task,
          join: ts in "task_sessions",
          on: ts.task_id == t.id,
          where: ts.session_id in ^session_ids,
          preload: [:state],
          order_by: [asc: ts.session_id, desc: t.priority, asc: t.created_at],
          select: {ts.session_id, t}
        )
        |> Repo.all()

      Enum.group_by(rows, fn {session_id, _} -> session_id end, fn {_, task} -> task end)
    end
  end

  @doc """
  Returns the session IDs linked to the given task via task_sessions.
  Used to trigger team member status updates when a task is completed.
  """
  def list_session_ids_for_task(task_id) do
    from(ts in "task_sessions",
      where: ts.task_id == ^task_id,
      select: ts.session_id
    )
    |> Repo.all()
  end

  @doc """
  Returns the list of tasks for a specific team. Default limit: 500.
  Pass `limit: n` to override.
  """
  def list_tasks_for_team(team_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    Task
    |> where([t], t.team_id == ^team_id)
    |> preload([:state, :tags])
    |> order_by([t], asc: t.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns team tasks with their linked session IDs from task_sessions.
  Each task has a :session_ids key with a list of session integer IDs.
  """
  def list_tasks_for_team_with_sessions(team_id) do
    tasks = list_tasks_for_team(team_id)
    task_ids = Enum.map(tasks, & &1.id)

    session_rows =
      from(ts in "task_sessions",
        where: ts.task_id in ^task_ids,
        select: {ts.task_id, ts.session_id}
      )
      |> Repo.all()

    sessions_by_task =
      Enum.group_by(session_rows, fn {task_id, _} -> task_id end, fn {_, sid} -> sid end)

    Enum.map(tasks, fn t ->
      %{t | session_ids: Map.get(sessions_by_task, t.id, [])}
    end)
  end

  @doc """
  Returns the current in-progress task for a session (state_id = 2), or nil.
  """
  def get_current_task_for_session(session_id) do
    Task
    |> join(:inner, [t], ts in "task_sessions", on: ts.task_id == t.id)
    |> where(
      [t, ts],
      ts.session_id == ^session_id and t.state_id == ^WorkflowState.in_progress_id()
    )
    |> order_by([t], desc: t.updated_at)
    |> limit(1)
    |> preload([:state])
    |> Repo.one()
  end

  @doc """
  Counts tasks for a specific session.
  """
  def count_tasks_for_session(session_id) do
    QueryHelpers.count_for_session_join(Task, session_id, "task_sessions")
  end

  @doc """
  Returns tasks that have the given tag_id linked via task_tags.
  """
  def list_tasks_for_tag(tag_id, opts \\ []) do
    Task
    |> join(:inner, [t], tt in "task_tags", on: tt.task_id == t.id)
    |> where([t, tt], tt.tag_id == ^tag_id)
    |> QueryBuilder.maybe_where(opts, :state_id)
    |> maybe_since(opts)
    |> maybe_stale_since(opts)
    |> order_by([t], desc: t.priority, asc: t.created_at)
    |> preload(^@full_task_preloads)
    |> QueryBuilder.maybe_limit(opts)
    |> QueryBuilder.maybe_offset(opts)
    |> Repo.all()
  end

  @doc """
  Returns tasks created by the given session (via created_by_session_id).
  """
  def list_tasks_created_by_session(session_id, opts \\ []) do
    Task
    |> where([t], t.created_by_session_id == ^session_id)
    |> QueryBuilder.maybe_where(opts, :state_id)
    |> maybe_since(opts)
    |> maybe_stale_since(opts)
    |> order_by([t], desc: t.priority, asc: t.created_at)
    |> preload([:state, :tags])
    |> QueryBuilder.maybe_limit(opts)
    |> QueryBuilder.maybe_offset(opts)
    |> Repo.all()
  end

  @doc """
  Lists tasks for a project with optional filtering and pagination.

  ## Options
    - `:sort_by` - "created_asc", "priority", or default (position asc, created desc)
    - `:state_id` - filter by workflow state
    - `:include_archived` - include archived tasks (default: false)
    - `:limit` / `:offset` - pagination
  """
  def list_tasks_for_project(project_id, opts \\ []) when is_integer(project_id) do
    sort_by = Keyword.get(opts, :sort_by, "created_desc")

    order =
      case sort_by do
        "created_desc" -> [desc: :created_at]
        "created_asc" -> [asc: :created_at]
        "priority" -> [desc: :priority, asc: :position]
        _ -> [asc: :position, desc: :created_at]
      end

    base_project_tasks_query(project_id, opts)
    |> maybe_since(opts)
    |> maybe_stale_since(opts)
    |> order_by(^order)
    |> QueryBuilder.maybe_limit(opts)
    |> QueryBuilder.maybe_offset(opts)
    |> preload(^@full_task_preloads)
    |> Repo.all()
  end

  @doc "Counts tasks for a project with optional filtering."
  def count_tasks_for_project(project_id, opts \\ []) when is_integer(project_id) do
    base_project_tasks_query(project_id, opts)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Search tasks using PostgreSQL full-text search.
  """
  def search_tasks(query, project_id \\ nil, opts \\ []) when is_binary(query) do
    extra_where =
      if project_id, do: dynamic([t], t.project_id == ^project_id)

    PgSearch.search_for(query,
      table: "tasks",
      schema: Task,
      search_columns: ["title", "description"],
      sql_filter: if(project_id, do: "AND t.project_id = $2", else: ""),
      sql_params: if(project_id, do: [project_id], else: []),
      extra_where: extra_where,
      order_by: [desc: :priority, desc: :created_at],
      preload: @full_task_preloads,
      limit: Keyword.get(opts, :limit)
    )
  end

  defp task_order(query, "created_asc"), do: order_by(query, [t], asc: t.created_at)

  defp task_order(query, "priority"),
    do: order_by(query, [t], desc: t.priority, desc: t.created_at)

  defp task_order(query, _), do: order_by(query, [t], desc: t.created_at)

  defp base_tasks_query(opts) do
    include_archived = Keyword.get(opts, :include_archived, false)

    Task
    |> then(fn q -> if include_archived, do: q, else: where(q, [t], t.archived == false) end)
    |> QueryBuilder.maybe_where(opts, :state_id)
    |> maybe_since(opts)
    |> maybe_stale_since(opts)
  end

  # Filters to tasks whose state changed (updated_at) within the given window.
  # Applied when `opts[:since]` is a `%DateTime{}`.
  defp maybe_since(query, opts) do
    case Keyword.get(opts, :since) do
      nil -> query
      %DateTime{} = dt -> where(query, [t], t.updated_at >= ^dt)
    end
  end

  # Filters to non-terminal tasks that have NOT been updated since the given cutoff.
  # Applied when `opts[:stale_since]` is a `%DateTime{}`.
  # Terminal state: Done (id=3). All others (To Do, In Progress, In Review) qualify.
  defp maybe_stale_since(query, opts) do
    case Keyword.get(opts, :stale_since) do
      nil ->
        query

      %DateTime{} = dt ->
        done_id = WorkflowState.done_id()
        where(query, [t], t.state_id != ^done_id and t.updated_at < ^dt)
    end
  end

  # --- Scope-aware queries ---

  @doc """
  Lists tasks for a given `EyeInTheSky.Scope`.

  - Project scope: delegates to `list_tasks_for_project/2`.
  - Workspace scope: returns tasks across all projects in the workspace,
    preloads :project so callers can show the project label.

  Accepts the same opts as `list_tasks_for_project/2`:
  `sort_by`, `include_archived`, `state_id`, `limit`, `offset`.
  """
  def list_tasks_for_scope(scope, opts \\ [])

  def list_tasks_for_scope(%EyeInTheSky.Scope{type: :project, project_id: pid}, opts) do
    list_tasks_for_project(pid, opts)
  end

  def list_tasks_for_scope(%EyeInTheSky.Scope{type: :workspace, workspace_id: wid}, opts) do
    sort_by = Keyword.get(opts, :sort_by, "created_desc")
    include_archived = Keyword.get(opts, :include_archived, false)

    order =
      case sort_by do
        "created_desc" -> [desc: :created_at]
        "created_asc" -> [asc: :created_at]
        "priority" -> [desc: :priority, asc: :position]
        _ -> [asc: :position, desc: :created_at]
      end

    query =
      from t in Task,
        join: p in EyeInTheSky.Projects.Project,
        on: t.project_id == p.id and p.workspace_id == ^wid,
        preload: [project: p]

    query = if include_archived, do: query, else: where(query, [t], t.archived == false)
    query = QueryBuilder.maybe_where(query, opts, :state_id)

    query
    |> order_by(^order)
    |> QueryBuilder.maybe_limit(opts)
    |> QueryBuilder.maybe_offset(opts)
    |> preload(^@full_task_preloads)
    |> Repo.all()
  end

  defp base_project_tasks_query(project_id, opts) do
    include_archived = Keyword.get(opts, :include_archived, false)

    query = from(t in Task, where: t.project_id == ^project_id)
    query = if include_archived, do: query, else: where(query, [t], t.archived == false)
    QueryBuilder.maybe_where(query, opts, :state_id)
  end
end
