defmodule EyeInTheSkyWeb.Tasks do
  @moduledoc """
  The Tasks context for managing tasks and workflow states.
  """

  use EyeInTheSkyWeb.CrudHelpers, schema: EyeInTheSkyWeb.Tasks.Task

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Tasks.{Task, WorkflowState, Tag, ChecklistItem}
  alias EyeInTheSkyWeb.QueryHelpers
  alias EyeInTheSkyWeb.QueryBuilder
  alias EyeInTheSkyWeb.Search.PgSearch
  alias EyeInTheSkyWeb.Notes

  # Workflow state ID accessors — source of truth is WorkflowState
  defdelegate state_todo, to: WorkflowState, as: :todo_id
  defdelegate state_in_progress, to: WorkflowState, as: :in_progress_id
  defdelegate state_in_review, to: WorkflowState, as: :in_review_id
  defdelegate state_done, to: WorkflowState, as: :done_id

  # Task functions

  @doc """
  Returns the list of tasks.

  Options:
  - `:limit` - maximum number of tasks to return (default: nil = all)
  - `:offset` - number of tasks to skip (default: 0)
  - `:state_id` - filter by workflow state ID (default: nil = all)
  """
  def list_tasks(opts \\ []) do
    base_tasks_query(opts)
    |> preload([:state, :tags, :sessions, :checklist_items])
    |> order_by([t], desc: t.created_at)
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

  defp base_tasks_query(opts) do
    Task
    |> QueryBuilder.maybe_where(opts, :state_id)
  end

  @doc """
  Returns the list of tasks for a specific agent.
  """
  def list_tasks_for_agent(agent_id) do
    Task
    |> where([t], t.agent_id == ^agent_id)
    |> preload([:state, :tags, :sessions, :checklist_items])
    |> order_by([t],
      desc: fragment("CASE WHEN ? IS NULL THEN 0 ELSE 1 END", t.archived),
      desc: t.priority,
      asc: t.created_at
    )
    |> Repo.all()
  end

  @doc """
  Returns the list of tasks for a specific session.
  """
  def list_tasks_for_session(session_id, opts \\ []) do
    QueryHelpers.for_session_join(Task, session_id, "task_sessions",
      preload: [:state, :tags],
      order_by: [desc: :priority, asc: :created_at],
      limit: Keyword.get(opts, :limit),
      offset: Keyword.get(opts, :offset)
    )
    |> Notes.with_notes_count()
  end

  @doc """
  Returns the list of tasks for a specific team.
  """
  def list_tasks_for_team(team_id) do
    Task
    |> where([t], t.team_id == ^team_id)
    |> preload([:state, :tags])
    |> order_by([t], asc: t.id)
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
      Map.put(t, :session_ids, Map.get(sessions_by_task, t.id, []))
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
  Gets a single task.

  Raises `Ecto.NoResultsError` if the Task does not exist.
  """
  def get_task!(id) do
    Task
    |> preload([:state, :tags, :sessions, :checklist_items])
    |> Repo.get!(id)
  end

  @doc """
  Gets a single task by UUID.

  Raises `Ecto.NoResultsError` if the Task does not exist.
  """
  def get_task_by_uuid!(uuid) do
    Task
    |> preload([:state, :tags, :sessions, :checklist_items])
    |> Repo.get_by!(uuid: uuid)
  end

  @doc """
  Gets a task by UUID, falling back to integer ID if UUID lookup misses.
  Accepts a string that is either a UUID or a stringified integer ID.
  Raises `Ecto.NoResultsError` if nothing is found.
  """
  def get_task_by_uuid_or_id!(id_str) do
    task =
      case Repo.get_by(Task, uuid: id_str) do
        nil ->
          case Integer.parse(id_str) do
            {int_id, ""} -> Repo.get!(Task, int_id)
            _ -> raise Ecto.NoResultsError, queryable: Task
          end

        task ->
          task
      end

    Repo.preload(task, [:state, :tags, :sessions, :checklist_items])
  end

  @doc """
  Creates a task.
  """
  def create_task(attrs \\ %{}) do
    result =
      %Task{}
      |> Task.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, task} -> broadcast_change({:ok, task})
      _ -> :ok
    end

    result
  end

  @doc """
  Creates a task from form params (LiveView event data).

  Handles UUID generation, timestamp creation, tag parsing, and tag assignment.
  Returns `{:ok, task}` or `{:error, changeset}`.

  ## Options

    * `:project_id` - required for project-scoped task creation
    * `:session_id` - optional, links the task to a session after creation

  """
  def create_task_from_form(params, opts \\ []) do
    project_id = opts[:project_id]
    session_id = opts[:session_id]

    title = params["title"]
    description = params["description"]
    state_id = parse_form_int(params["state_id"], 0)
    priority = parse_form_int(params["priority"], 0)
    tags_string = params["tags"] || ""

    tag_names =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    now = DateTime.utc_now() |> DateTime.to_iso8601()

    attrs = %{
      uuid: Ecto.UUID.generate(),
      title: title,
      description: description,
      state_id: if(state_id > 0, do: state_id, else: WorkflowState.todo_id()),
      priority: priority,
      created_at: now,
      updated_at: now
    }

    attrs = if project_id, do: Map.put(attrs, :project_id, project_id), else: attrs

    case create_task(attrs) do
      {:ok, task} ->
        if tag_names != [], do: replace_task_tags(task.id, tag_names)
        if session_id, do: link_session_to_task(task.id, session_id)
        {:ok, Repo.preload(task, [:state, :tags, :sessions, :checklist_items])}

      error ->
        error
    end
  end

  @doc """
  Quick-creates a task with just a title, state, and project.
  Used by kanban quick-add and similar minimal-input flows.
  """
  def quick_create_task(title, state_id, project_id) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    create_task(%{
      uuid: Ecto.UUID.generate(),
      title: title,
      state_id: state_id,
      priority: 0,
      project_id: project_id,
      created_at: now,
      updated_at: now
    })
  end

  defp parse_form_int(nil, default), do: default

  defp parse_form_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_form_int(val, _default) when is_integer(val), do: val
  defp parse_form_int(_, default), do: default

  @doc """
  Updates a task.
  """
  def update_task(%Task{} = task, attrs) do
    result =
      task
      |> Task.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, task} -> broadcast_change({:ok, task})
      _ -> :ok
    end

    result
  end

  @doc """
  Updates a task's state.
  """
  def update_task_state(%Task{} = task, state_id) do
    update_task(task, %{state_id: state_id})
  end

  @doc """
  Archives a task (sets archived = true). Non-destructive.
  """
  def archive_task(%Task{} = task) do
    result =
      update_task(task, %{archived: true, updated_at: DateTime.utc_now() |> DateTime.to_iso8601()})

    case result do
      {:ok, updated} -> broadcast_change({:updated, updated})
      _ -> :ok
    end

    result
  end

  @doc """
  Unarchives a task (sets archived = false).
  """
  def unarchive_task(%Task{} = task) do
    update_task(task, %{archived: false, updated_at: DateTime.utc_now() |> DateTime.to_iso8601()})
  end

  @doc """
  Bulk-updates position for a list of tasks within a column.
  `ordered_uuids` is a list of task UUIDs in the desired order (index = position).
  """
  def reorder_tasks(ordered_uuids) when is_list(ordered_uuids) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    ordered_uuids
    |> Enum.with_index(1)
    |> Enum.each(fn {uuid, position} ->
      Repo.update_all(
        from(t in Task, where: t.uuid == ^uuid),
        set: [position: position, updated_at: now]
      )
    end)

    :ok
  end

  @doc "Deletes a task."
  def delete_task(%Task{} = task) do
    result = Repo.delete(task)

    case result do
      {:ok, _} -> broadcast_change({:deleted, task})
      _ -> :ok
    end

    result
  end

  @doc """
  Deletes a task and its join-table associations (task_tags, task_sessions, commit_tasks).
  Returns {:ok, task} or {:error, reason}.
  """
  def delete_task_with_associations(%Task{} = task) do
    Repo.delete_all(from(t in "task_tags", where: t.task_id == ^task.id))
    Repo.delete_all(from(t in "task_sessions", where: t.task_id == ^task.id))
    Repo.delete_all(from(t in "commit_tasks", where: t.task_id == ^task.id))
    delete_task(task)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking task changes.
  """
  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  @doc """
  Search tasks using PostgreSQL full-text search.
  """
  def search_tasks(query, project_id \\ nil) when is_binary(query) do
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
      preload: [:state, :tags, :sessions, :checklist_items]
    )
  end

  # Workflow State functions

  @doc """
  Returns the list of workflow states.
  """
  def list_workflow_states do
    WorkflowState
    |> order_by([ws], asc: ws.position)
    |> Repo.all()
  end

  @doc """
  Reorder workflow states by a list of IDs in desired order.
  The position unique constraint is DEFERRABLE INITIALLY DEFERRED, so uniqueness
  is checked at commit rather than per-statement — no temp negative positions needed.
  """
  def reorder_workflow_states(ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index(1)
      |> Enum.each(fn {id, idx} ->
        from(ws in WorkflowState, where: ws.id == ^id)
        |> Repo.update_all(set: [position: idx])
      end)
    end)
  end

  @doc """
  Gets a single workflow state.
  """
  def get_workflow_state!(id) do
    Repo.get!(WorkflowState, id)
  end

  @doc """
  Gets a workflow state by name.
  """
  def get_workflow_state_by_name(name) do
    Repo.get_by(WorkflowState, name: name)
  end

  # Tag functions

  @doc """
  Returns the list of tags.
  """
  def list_tags do
    Repo.all(Tag)
  end

  @doc """
  Gets a single tag.
  """
  def get_tag!(id) do
    Repo.get!(Tag, id)
  end

  @doc """
  Updates a tag's attributes (e.g., color).
  """
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets or creates a tag by name.
  """
  def get_or_create_tag(name) do
    case Repo.get_by(Tag, name: name) do
      nil ->
        %Tag{}
        |> Tag.changeset(%{name: name})
        |> Repo.insert()

      tag ->
        {:ok, tag}
    end
  end

  @doc """
  Links a session to a task via the task_sessions join table.
  Uses on_conflict: :nothing to silently skip duplicates.
  """
  def link_session_to_task(task_id, session_id)
      when is_integer(task_id) and is_integer(session_id) do
    {count, _} =
      Repo.insert_all("task_sessions", [%{task_id: task_id, session_id: session_id}],
        on_conflict: :nothing
      )

    {:ok, count}
  end

  @doc """
  Returns true if the given task is linked to the given session via task_sessions.
  Used to gate EITS-CMD task mutations to tasks the session created or was linked to.
  """
  def task_linked_to_session?(task_id, session_id)
      when is_integer(task_id) and is_integer(session_id) do
    import Ecto.Query

    Repo.exists?(
      from ts in "task_sessions",
        where: ts.task_id == ^task_id and ts.session_id == ^session_id
    )
  end

  def task_linked_to_session?(_, _), do: false

  @doc """
  Replaces all tags on a task with the given list of tag names.
  Deletes existing tag associations and inserts new ones.
  No-op if tag_names is empty (leaves existing tags unchanged).
  """
  def replace_task_tags(_task_id, []), do: :ok

  def replace_task_tags(task_id, tag_names) when is_list(tag_names) do
    tag_rows =
      Enum.flat_map(tag_names, fn tag_name ->
        case get_or_create_tag(tag_name) do
          {:ok, tag} -> [%{task_id: task_id, tag_id: tag.id}]
          _ -> []
        end
      end)

    Repo.delete_all(from(t in "task_tags", where: t.task_id == ^task_id))
    Repo.insert_all("task_tags", tag_rows, on_conflict: :nothing)
  end

  @doc """
  Links a tag to a task via the task_tags join table.
  """
  def link_tag_to_task(task_id, tag_id)
      when is_integer(task_id) and is_integer(tag_id) do
    {count, _} =
      Repo.insert_all("task_tags", [%{task_id: task_id, tag_id: tag_id}], on_conflict: :nothing)

    {:ok, count}
  end

  @doc """
  Unlinks a session from a task by deleting the task_sessions row.
  Returns the number of rows deleted.
  """
  def unlink_session_from_task(task_id, session_id)
      when is_integer(task_id) and is_integer(session_id) do
    {count, _} =
      from(ts in "task_sessions",
        where: ts.task_id == ^task_id and ts.session_id == ^session_id
      )
      |> Repo.delete_all()

    {:ok, count}
  end

  # PubSub

  defp broadcast_change({tag, task}) when tag in [:ok, :deleted] do
    EyeInTheSkyWeb.Events.task_updated(task)
  end

  defp broadcast_change(_) do
    EyeInTheSkyWeb.Events.tasks_changed()
  end

  # Checklist Items

  @doc """
  Lists checklist items for a task, ordered by position.
  """
  def list_checklist_items(task_id) do
    ChecklistItem
    |> where([c], c.task_id == ^task_id)
    |> order_by([c], asc: c.position, asc: c.id)
    |> Repo.all()
  end

  @doc """
  Creates a checklist item for a task.
  """
  def create_checklist_item(attrs) do
    %ChecklistItem{}
    |> ChecklistItem.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Toggles a checklist item's completed state.
  """
  def toggle_checklist_item(id) do
    item = Repo.get!(ChecklistItem, id)

    item
    |> ChecklistItem.changeset(%{completed: !item.completed})
    |> Repo.update()
  end

  @doc """
  Deletes a checklist item.
  """
  def delete_checklist_item(id) do
    Repo.get!(ChecklistItem, id)
    |> Repo.delete()
  end
end
