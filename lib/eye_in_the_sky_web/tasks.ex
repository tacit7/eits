defmodule EyeInTheSkyWeb.Tasks do
  @moduledoc """
  The Tasks context for managing tasks and workflow states.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Tasks.{Task, WorkflowState, Tag}
  alias EyeInTheSkyWeb.QueryHelpers
  alias EyeInTheSkyWeb.Search.FTS5

  # Task functions

  @doc """
  Returns the list of tasks.
  """
  def list_tasks do
    Task
    |> preload([:state, :tags])
    |> Repo.all()
  end

  @doc """
  Returns the list of tasks for a specific agent.
  """
  def list_tasks_for_agent(agent_id) do
    Task
    |> where([t], t.agent_id == ^agent_id)
    |> preload([:state, :tags])
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
    |> preload([:state, :tags, :sessions])
    |> Repo.get!(id)
  end

  @doc """
  Creates a task.
  """
  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a task.
  """
  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
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
    Repo.delete(task)
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
        where(fallback_query, [t], t.project_id == ^Integer.to_string(project_id))
      else
        fallback_query
      end
      |> order_by([t], desc: t.priority, desc: t.created_at)

    FTS5.search(
      table: "tasks",
      fts_table: "task_search",
      schema: Task,
      query: query,
      join_key: "task_id",
      sql_filter: if(project_id, do: "AND t.project_id = ?", else: ""),
      sql_params: if(project_id, do: [Integer.to_string(project_id)], else: []),
      fallback_query: fallback_query,
      preload: [:state, :tags]
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
end
