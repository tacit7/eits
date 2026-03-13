defmodule EyeInTheSkyWeb.Tasks do
  @moduledoc """
  The Tasks context for managing tasks and workflow states.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Tasks.{Task, WorkflowState, Tag}
  alias EyeInTheSkyWeb.QueryHelpers
  alias EyeInTheSkyWeb.Search.FTS5

  # Workflow state IDs (matches workflow_states table)
  @state_todo 1
  @state_in_progress 2
  @state_in_review 4
  @state_done 3

  def state_todo, do: @state_todo
  def state_in_progress, do: @state_in_progress
  def state_in_review, do: @state_in_review
  def state_done, do: @state_done

  # Task functions

  @doc """
  Returns the list of tasks.

  Options:
  - `:limit` - maximum number of tasks to return (default: nil = all)
  - `:offset` - number of tasks to skip (default: 0)
  - `:state_id` - filter by workflow state ID (default: nil = all)
  """
  def list_tasks(opts \\ []) do
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)
    state_id = Keyword.get(opts, :state_id)

    query =
      Task
      |> preload([:state, :tags, :agents])
      |> order_by([t], desc: t.created_at)

    query = if state_id, do: where(query, [t], t.state_id == ^state_id), else: query
    query = if limit, do: limit(query, ^limit), else: query
    query = if offset > 0, do: offset(query, ^offset), else: query

    Repo.all(query)
  end

  @doc """
  Returns the count of tasks matching the given filters.

  Options:
  - `:state_id` - filter by workflow state ID (default: nil = all)
  """
  def count_tasks(opts \\ []) do
    state_id = Keyword.get(opts, :state_id)

    query = Task

    query = if state_id, do: where(query, [t], t.state_id == ^state_id), else: query

    Repo.aggregate(query, :count, :id)
  end

  @doc """
  Returns the list of tasks for a specific agent.
  """
  def list_tasks_for_agent(agent_id) do
    Task
    |> where([t], t.agent_id == ^agent_id)
    |> preload([:state, :tags, :agents])
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
  def list_tasks_for_session(session_id) do
    QueryHelpers.for_session_join(Task, session_id, "task_sessions",
      preload: [:state, :tags],
      order_by: [desc: :priority, asc: :created_at]
    )
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
  Returns the current in-progress task for a session (state_id = 2), or nil.
  """
  def get_current_task_for_session(session_id) do
    Task
    |> join(:inner, [t], ts in "task_sessions", on: ts.task_id == t.id)
    |> where([t, ts], ts.session_id == ^session_id and t.state_id == @state_in_progress)
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
    |> preload([:state, :tags, :agents])
    |> Repo.get!(id)
  end

  @doc """
  Gets a single task by UUID.

  Raises `Ecto.NoResultsError` if the Task does not exist.
  """
  def get_task_by_uuid!(uuid) do
    Task
    |> preload([:state, :tags, :agents])
    |> Repo.get_by!(uuid: uuid)
  end

  @doc """
  Gets a task by UUID, falling back to integer ID if UUID lookup misses.
  Accepts a string that is either a UUID or a stringified integer ID.
  Raises `Ecto.NoResultsError` if nothing is found.
  """
  def get_task_by_uuid_or_id!(id_str) do
    query = Task |> preload([:state, :tags, :agents])

    case Repo.get_by(query, uuid: id_str) do
      nil ->
        case Integer.parse(id_str) do
          {int_id, ""} -> Repo.get!(query, int_id)
          _ -> raise Ecto.NoResultsError, queryable: Task
        end

      task ->
        task
    end
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
  Deletes a task.
  """
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
  Search tasks using FTS5.
  Requires task_search FTS5 table in database.
  """
  def search_tasks(query, project_id \\ nil) when is_binary(query) do
    pattern = "%#{query}%"

    fallback_query =
      from t in Task,
        where: ilike(t.title, ^pattern) or ilike(t.description, ^pattern)

    fallback_query =
      if project_id do
        where(fallback_query, [t], t.project_id == ^project_id)
      else
        fallback_query
      end
      |> order_by([t], desc: t.priority, desc: t.created_at)

    FTS5.search(
      table: "tasks",
      schema: Task,
      query: query,
      search_columns: ["title", "description"],
      sql_filter: if(project_id, do: "AND t.project_id = $2", else: ""),
      sql_params: if(project_id, do: [project_id], else: []),
      fallback_query: fallback_query,
      preload: [:state, :tags, :agents]
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
    Repo.insert_all("task_sessions", [%{task_id: task_id, session_id: session_id}],
      on_conflict: :nothing
    )
  end

  @doc """
  Replaces all tags on a task with the given list of tag names.
  Deletes existing tag associations and inserts new ones.
  No-op if tag_names is empty (leaves existing tags unchanged).
  """
  def replace_task_tags(_task_id, []), do: :ok

  def replace_task_tags(task_id, tag_names) when is_list(tag_names) do
    Repo.delete_all(from(t in "task_tags", where: t.task_id == ^task_id))

    Enum.each(tag_names, fn tag_name ->
      case get_or_create_tag(tag_name) do
        {:ok, tag} ->
          Repo.insert_all("task_tags", [%{task_id: task_id, tag_id: tag.id}],
            on_conflict: :nothing
          )

        _ ->
          :ok
      end
    end)
  end

  @doc """
  Links a tag to a task via the task_tags join table.
  """
  def link_tag_to_task(task_id, tag_id)
      when is_integer(task_id) and is_integer(tag_id) do
    Repo.insert_all("task_tags", [%{task_id: task_id, tag_id: tag_id}], on_conflict: :nothing)
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

    count
  end

  # PubSub

  defp broadcast_change({tag, task}) when tag in [:ok, :deleted] do
    do_broadcast_tasks_changed(task)
  end

  defp broadcast_change(_) do
    Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "tasks", :tasks_changed)
  end

  defp do_broadcast_tasks_changed(task) do
    Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "tasks", :tasks_changed)

    if task.project_id do
      Phoenix.PubSub.broadcast(
        EyeInTheSkyWeb.PubSub,
        "tasks:#{task.project_id}",
        :tasks_changed
      )
    end
  end
end
