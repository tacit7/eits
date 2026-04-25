defmodule EyeInTheSky.Tasks do
  @moduledoc """
  The Tasks context for managing tasks and workflow states.
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Tasks.Task

  require Logger
  import Ecto.Query, warn: false
  alias EyeInTheSky.Notes
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Tasks.{Task, WorkflowState}
  alias EyeInTheSky.Utils.ToolHelpers

  @full_task_preloads [:state, :tags, :sessions, :checklist_items]

  # Workflow state ID accessors — source of truth is WorkflowState
  defdelegate state_todo, to: WorkflowState, as: :todo_id
  defdelegate state_in_progress, to: WorkflowState, as: :in_progress_id
  defdelegate state_in_review, to: WorkflowState, as: :in_review_id
  defdelegate state_done, to: WorkflowState, as: :done_id

  # Delegates to sub-contexts (backward-compatible)
  defdelegate list_workflow_states(), to: EyeInTheSky.WorkflowStates
  defdelegate reorder_workflow_states(ids), to: EyeInTheSky.WorkflowStates
  defdelegate get_workflow_state!(id), to: EyeInTheSky.WorkflowStates
  defdelegate get_workflow_state_by_name(name), to: EyeInTheSky.WorkflowStates

  defdelegate list_tags(), to: EyeInTheSky.TaskTags
  defdelegate get_tag!(id), to: EyeInTheSky.TaskTags
  defdelegate update_tag(tag, attrs), to: EyeInTheSky.TaskTags
  defdelegate get_or_create_tag(name), to: EyeInTheSky.TaskTags
  defdelegate replace_task_tags(task_id, tag_names), to: EyeInTheSky.TaskTags
  defdelegate link_tag_to_task(task_id, tag_id), to: EyeInTheSky.TaskTags

  defdelegate list_checklist_items(task_id), to: EyeInTheSky.ChecklistItems
  defdelegate create_checklist_item(attrs), to: EyeInTheSky.ChecklistItems
  defdelegate toggle_checklist_item(id), to: EyeInTheSky.ChecklistItems
  defdelegate delete_checklist_item(id), to: EyeInTheSky.ChecklistItems

  # Task functions

  # Delegates to Tasks.Queries sub-module
  defdelegate list_tasks(opts \\ []), to: EyeInTheSky.Tasks.Queries
  defdelegate count_tasks(opts \\ []), to: EyeInTheSky.Tasks.Queries
  defdelegate list_tasks_for_agent(agent_id, opts \\ []), to: EyeInTheSky.Tasks.Queries
  defdelegate list_tasks_for_session(session_id, opts \\ []), to: EyeInTheSky.Tasks.Queries
  defdelegate list_tasks_for_sessions(session_ids), to: EyeInTheSky.Tasks.Queries
  defdelegate list_session_ids_for_task(task_id), to: EyeInTheSky.Tasks.Queries
  defdelegate list_tasks_for_team(team_id), to: EyeInTheSky.Tasks.Queries
  defdelegate list_tasks_for_team_with_sessions(team_id), to: EyeInTheSky.Tasks.Queries
  defdelegate get_current_task_for_session(session_id), to: EyeInTheSky.Tasks.Queries
  defdelegate count_tasks_for_session(session_id), to: EyeInTheSky.Tasks.Queries
  defdelegate list_tasks_created_by_session(session_id, opts \\ []), to: EyeInTheSky.Tasks.Queries

  @doc """
  Gets a single task. Returns `{:ok, task}` or `{:error, :not_found}`.
  """
  def get_task(id) do
    case Task
         |> preload(^@full_task_preloads)
         |> Repo.get(id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  @doc """
  Gets a single task.

  Raises `Ecto.NoResultsError` if the Task does not exist.
  """
  def get_task!(id) do
    Task
    |> preload(^@full_task_preloads)
    |> Repo.get!(id)
  end

  @doc """
  Gets a single task by UUID.

  Raises `Ecto.NoResultsError` if the Task does not exist.
  """
  def get_task_by_uuid!(uuid) do
    Task
    |> preload(^@full_task_preloads)
    |> Repo.get_by!(uuid: uuid)
  end

  @doc """
  Gets a task by UUID, falling back to integer ID if UUID lookup misses.
  Accepts a string that is either a UUID or a stringified integer ID.
  Raises `Ecto.NoResultsError` if nothing is found.
  """
  def get_task_by_uuid_or_id!(id_str) do
    task =
      if int_id = ToolHelpers.parse_int(id_str) do
        Repo.get!(Task, int_id)
      else
        Repo.get_by!(Task, uuid: id_str)
      end

    Repo.preload(task, @full_task_preloads)
  end

  @doc """
  Returns `{:ok, {integer_id, uuid}}` for a task identified by an integer ID or UUID string,
  or `{:error, :not_found}` if no task is found. No preloads.
  """
  def get_task_ids(id_str) do
    id_str = to_string(id_str)

    task =
      if int_id = ToolHelpers.parse_int(id_str) do
        Repo.get(Task, int_id)
      else
        Repo.get_by(Task, uuid: id_str)
      end

    case task do
      nil -> {:error, :not_found}
      t -> {:ok, {t.id, t.uuid}}
    end
  end

  @doc """
  Returns `{integer_id, uuid}` for a task identified by an integer ID or UUID string.
  No preloads — use this when only the IDs are needed.
  Raises `Ecto.NoResultsError` if nothing is found.
  """
  def get_task_ids!(id_str) do
    case get_task_ids(id_str) do
      {:ok, ids} -> ids
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Task
    end
  end

  @doc """
  Creates a task.
  """
  def create_task(attrs \\ %{}) do
    now = DateTime.utc_now()

    attrs =
      attrs
      |> Map.put_new(:uuid, Ecto.UUID.generate())
      |> Map.put_new(:created_at, now)
      |> Map.put_new(:updated_at, now)

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
  Quick-creates a task with just a title, state, and project.
  Used by kanban quick-add and similar minimal-input flows.
  """
  def quick_create_task(title, state_id, project_id) do
    now = DateTime.utc_now()

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

  @doc """
  Updates a task.
  """
  def update_task(%Task{} = task, attrs) do
    attrs = Map.put_new(attrs, :updated_at, DateTime.utc_now())

    result =
      task
      |> Task.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, task} -> broadcast_change({:updated, task})
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
  Completes a task in a single transaction:
    1. Creates an annotation note with the given message
    2. Moves the task to Done state

  Returns `{:ok, %{task: task, note: note}}` or `{:error, step, changeset, changes}`.
  """
  def complete_task(%Task{} = task, message) when is_binary(message) and message != "" do
    done_state_id = WorkflowState.done_id()

    note_changeset =
      Notes.note_changeset(%{
        title: "Task completed",
        body: message,
        parent_type: "task",
        parent_id: to_string(task.id)
      })

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:note, note_changeset)
    |> Ecto.Multi.run(:task, fn _repo, _changes ->
      update_task_state(task, done_state_id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, changes} -> {:ok, changes}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Atomically claims a task for the given session in a single transaction:
    1. Acquires a row-level lock on the task (FOR UPDATE) to serialize concurrent claims
    2. Clears all existing task_sessions links
    3. Inserts the claimer's session link
    4. Transitions the task state to In Progress

  Returns `{:ok, updated_task}` or `{:error, reason}`.
  The PubSub broadcast fires after the transaction commits.
  """
  def claim_task(%Task{} = task, session_int_id) when is_integer(session_int_id) do
    in_progress_id = WorkflowState.in_progress_id()
    todo_id = WorkflowState.todo_id()
    now = DateTime.utc_now()

    result =
      Repo.transaction(fn ->
        locked_state =
          from(t in "tasks", where: t.id == ^task.id, select: t.state_id, lock: "FOR UPDATE")
          |> Repo.one()

        if is_nil(locked_state), do: Repo.rollback(:task_not_found)
        # Reject In Progress tasks as a duplicate claim attempt
        if locked_state == in_progress_id, do: Repo.rollback(:already_claimed)
        # Reject Done/In Review — claiming them would silently regress their state
        if locked_state != todo_id, do: Repo.rollback(:task_not_claimable)

        Repo.delete_all(from(ts in "task_sessions", where: ts.task_id == ^task.id))
        Repo.insert_all("task_sessions", [%{task_id: task.id, session_id: session_int_id}])

        changeset = Task.changeset(task, %{state_id: in_progress_id, updated_at: now})

        case Repo.update(changeset) do
          {:ok, updated} -> updated
          {:error, cs} -> Repo.rollback(cs)
        end
      end)

    case result do
      {:ok, updated} ->
        EyeInTheSky.Events.task_updated(updated)
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Archives a task (sets archived = true). Non-destructive.
  """
  def archive_task(%Task{} = task) do
    update_task(task, %{archived: true, updated_at: DateTime.utc_now()})
  end

  @doc """
  Unarchives a task (sets archived = false).
  """
  def unarchive_task(%Task{} = task) do
    update_task(task, %{archived: false, updated_at: DateTime.utc_now()})
  end

  @doc """
  Bulk-updates position for a list of tasks within a column.
  `ordered_uuids` is a list of task UUIDs in the desired order (index = position).
  """
  def reorder_tasks([]), do: :ok

  def reorder_tasks(ordered_uuids) when is_list(ordered_uuids) do
    now = DateTime.utc_now()

    {placeholders, extra_params} =
      ordered_uuids
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {uuid, pos}, {phs, params} ->
        base = 2 + length(params)
        {phs ++ ["($#{base}, $#{base + 1})"], params ++ [uuid, pos]}
      end)

    sql = """
    UPDATE tasks
    SET position = v.pos,
        updated_at = $1
    FROM (VALUES #{Enum.join(placeholders, ", ")}) AS v(uuid_val, pos)
    WHERE tasks.uuid = v.uuid_val::uuid
    """

    Ecto.Adapters.SQL.query!(Repo, sql, [now | extra_params])
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
    result =
      Repo.transaction(fn ->
        Repo.delete_all(from(t in "task_tags", where: t.task_id == ^task.id))
        Repo.delete_all(from(t in "task_sessions", where: t.task_id == ^task.id))
        Repo.delete_all(from(t in "commit_tasks", where: t.task_id == ^task.id))

        case Repo.delete(task) do
          {:ok, t} -> t
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, deleted} -> broadcast_change({:deleted, deleted})
      _ -> :ok
    end

    result
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking task changes.
  """
  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  defdelegate search_tasks(query, project_id \\ nil, opts \\ []), to: EyeInTheSky.Tasks.Queries

  # Delegates to TaskSessions context (session-linking operations)
  defdelegate link_session_to_task(task_id, session_id), to: EyeInTheSky.TaskSessions
  defdelegate task_linked_to_session?(task_id, session_id), to: EyeInTheSky.TaskSessions
  defdelegate unlink_session_from_task(task_id, session_id), to: EyeInTheSky.TaskSessions
  defdelegate active_task_count_for_session(session_id), to: EyeInTheSky.TaskSessions
  defdelegate transfer_session_ownership(task_id, new_session_id), to: EyeInTheSky.TaskSessions

  defdelegate list_tasks_for_project(project_id, opts \\ []), to: EyeInTheSky.Tasks.Queries
  defdelegate count_tasks_for_project(project_id, opts \\ []), to: EyeInTheSky.Tasks.Queries
  defdelegate list_tasks_for_scope(scope, opts \\ []), to: EyeInTheSky.Tasks.Queries

  # Delegates to Tasks.Associations sub-module
  defdelegate associate_task(task, params), to: EyeInTheSky.Tasks.Associations

  # PubSub

  defp broadcast_change({tag, task}) when tag in [:ok, :deleted, :updated] do
    EyeInTheSky.Events.task_updated(task)
  end
end
