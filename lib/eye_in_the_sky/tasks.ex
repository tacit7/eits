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

  @full_task_preloads [:state, :tags, :sessions, :checklist_items, :agent]

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

  defdelegate list_tags(opts \\ []), to: EyeInTheSky.TaskTags
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
  Gets a task by UUID or ID string, returning `{:ok, task}` or `{:error, :not_found}`.
  Accepts a string that is either a UUID or a stringified integer ID.
  """
  def get_task_by_uuid_or_id(id_str) do
    id_str = to_string(id_str)

    task =
      if int_id = ToolHelpers.parse_int(id_str) do
        Repo.get(Task, int_id)
      else
        Repo.get_by(Task, uuid: id_str)
      end

    case task do
      nil -> {:error, :not_found}
      t -> {:ok, Repo.preload(t, @full_task_preloads)}
    end
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
      {:ok, task} -> EyeInTheSky.Events.task_updated(task)
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

    case task |> Task.changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        EyeInTheSky.Events.task_updated(updated)
        {:ok, Repo.preload(updated, @full_task_preloads, force: true)}

      error ->
        error
    end
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
      Ecto.Multi.new()
      |> Ecto.Multi.run(:validate_task, fn repo, _changes ->
        locked_state =
          from(t in "tasks", where: t.id == ^task.id, select: t.state_id, lock: "FOR UPDATE")
          |> repo.one()

        cond do
          is_nil(locked_state) -> {:error, :task_not_found}
          locked_state == in_progress_id -> {:error, :already_claimed}
          locked_state != todo_id -> {:error, :task_not_claimable}
          true -> {:ok, locked_state}
        end
      end)
      |> Ecto.Multi.run(:delete_old_sessions, fn repo, _changes ->
        {count, _} = repo.delete_all(from(ts in "task_sessions", where: ts.task_id == ^task.id))
        {:ok, count}
      end)
      |> Ecto.Multi.run(:add_new_session, fn repo, _changes ->
        repo.insert_all("task_sessions", [%{task_id: task.id, session_id: session_int_id}])
      end)
      |> Ecto.Multi.update(:update_task, Task.changeset(task, %{state_id: in_progress_id, updated_at: now}))
      |> Repo.transaction()

    case result do
      {:ok, %{update_task: updated}} ->
        EyeInTheSky.Events.task_updated(updated)
        {:ok, Repo.preload(updated, @full_task_preloads, force: true)}

      {:error, _key, reason, _changes} ->
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
    pairs = Enum.with_index(ordered_uuids, 1)
    uuids = Enum.map(pairs, fn {u, _} -> u end)
    positions = Enum.map(pairs, fn {_, p} -> p end)

    Repo.query!(
      """
      UPDATE tasks
      SET position = pos_list.pos,
          updated_at = $3
      FROM unnest($1::text[], $2::int[]) AS pos_list(uuid, pos)
      WHERE tasks.uuid::text = pos_list.uuid
      """,
      [uuids, positions, now]
    )

    :ok
  end

  @doc "Deletes a task."
  def delete_task(%Task{} = task) do
    result = Repo.delete(task)

    case result do
      {:ok, _} -> EyeInTheSky.Events.task_updated(task)
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
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(:delete_task_tags, from(t in "task_tags", where: t.task_id == ^task.id))
      |> Ecto.Multi.delete_all(:delete_task_sessions, from(t in "task_sessions", where: t.task_id == ^task.id))
      |> Ecto.Multi.delete_all(:delete_commit_tasks, from(t in "commit_tasks", where: t.task_id == ^task.id))
      |> Ecto.Multi.delete(:delete_task, task)
      |> Repo.transaction()

    case result do
      {:ok, %{delete_task: deleted}} ->
        EyeInTheSky.Events.task_updated(deleted)
        {:ok, deleted}

      {:error, _key, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking task changes.
  """
  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  @doc """
  Returns `{:ok, session}` for the session currently holding the task, or `{:error, :none}`.
  Used to enrich conflict errors on claim so callers know who the current owner is.
  """
  def get_current_session_for_task(task_id) do
    query =
      from ts in "task_sessions",
        join: s in EyeInTheSky.Sessions.Session,
        on: s.id == ts.session_id,
        where: ts.task_id == ^task_id,
        select: s,
        limit: 1

    case Repo.one(query) do
      nil -> {:error, :none}
      session -> {:ok, session}
    end
  end

  @doc """
  Bulk-archives tasks by UUID strings or stringified integer IDs.
  Returns {archived_count, nil}.
  """
  def batch_archive_tasks([]), do: {0, nil}

  def batch_archive_tasks(id_strings) when is_list(id_strings) do
    {uuids, int_ids} = split_uuid_and_int_ids(id_strings)

    Repo.update_all(
      from(t in Task,
        where: t.uuid in ^uuids or t.id in ^int_ids
      ),
      set: [archived: true, updated_at: DateTime.utc_now()]
    )
  end

  @doc """
  Bulk-deletes tasks and their join-table associations in one transaction.
  Accepts UUID strings or stringified integer IDs.
  Returns {deleted_count, nil}.
  """
  def batch_delete_tasks_with_associations([]), do: {0, nil}

  def batch_delete_tasks_with_associations(id_strings) when is_list(id_strings) do
    {uuids, int_ids} = split_uuid_and_int_ids(id_strings)

    task_ids_query =
      from(t in Task,
        where: t.uuid in ^uuids or t.id in ^int_ids,
        select: t.id
      )

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:get_task_ids, fn repo, _changes ->
        task_ids = repo.all(task_ids_query)
        {:ok, task_ids}
      end)
      |> Ecto.Multi.run(:delete_task_tags, fn repo, %{get_task_ids: task_ids} ->
        repo.delete_all(from(tt in "task_tags", where: tt.task_id in ^task_ids))
      end)
      |> Ecto.Multi.run(:delete_task_sessions, fn repo, %{get_task_ids: task_ids} ->
        repo.delete_all(from(ts in "task_sessions", where: ts.task_id in ^task_ids))
      end)
      |> Ecto.Multi.run(:delete_commit_tasks, fn repo, %{get_task_ids: task_ids} ->
        repo.delete_all(from(ct in "commit_tasks", where: ct.task_id in ^task_ids))
      end)
      |> Ecto.Multi.run(:delete_tasks, fn repo, %{get_task_ids: task_ids} ->
        {deleted, _} = repo.delete_all(from(t in Task, where: t.id in ^task_ids))
        {:ok, deleted}
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{delete_tasks: count}} -> {count, nil}
      {:error, _key, _reason, _changes} -> {0, nil}
    end
  end

  defdelegate search_tasks(query, project_id \\ nil, opts \\ []), to: EyeInTheSky.Tasks.Queries

  @doc """
  Bulk-updates state for tasks by UUID strings or stringified integer IDs.
  Returns {updated_count, nil}.
  """
  def batch_update_task_state([], _state_id), do: {0, nil}

  def batch_update_task_state(id_strings, state_id) when is_list(id_strings) do
    {uuids, int_ids} = split_uuid_and_int_ids(id_strings)

    now = DateTime.utc_now()

    Repo.update_all(
      from(t in EyeInTheSky.Tasks.Task,
        where: t.uuid in ^uuids or t.id in ^int_ids
      ),
      set: [state_id: state_id, updated_at: now]
    )
  end

  # Delegates to TaskSessions context (session-linking operations)
  defdelegate link_session_to_task(task_id, session_id), to: EyeInTheSky.TaskSessions
  defdelegate task_linked_to_session?(task_id, session_id), to: EyeInTheSky.TaskSessions
  defdelegate unlink_session_from_task(task_id, session_id), to: EyeInTheSky.TaskSessions
  defdelegate active_task_count_for_session(session_id), to: EyeInTheSky.TaskSessions
  defdelegate transfer_session_ownership(task_id, new_session_id), to: EyeInTheSky.TaskSessions

  defdelegate list_tasks_for_tag(tag_id, opts \\ []), to: EyeInTheSky.Tasks.Queries
  defdelegate list_tasks_for_project(project_id, opts \\ []), to: EyeInTheSky.Tasks.Queries
  defdelegate count_tasks_for_project(project_id, opts \\ []), to: EyeInTheSky.Tasks.Queries
  defdelegate count_tasks_for_project_by_state(project_id), to: EyeInTheSky.Tasks.Queries
  defdelegate list_tasks_for_scope(scope, opts \\ []), to: EyeInTheSky.Tasks.Queries

  # Delegates to Tasks.Associations sub-module
  defdelegate associate_task(task, params), to: EyeInTheSky.Tasks.Associations

  # Splits a list of UUID strings or stringified integer IDs into two lists.
  # Returns {uuids, int_ids}.
  defp split_uuid_and_int_ids(id_strings) do
    Enum.reduce(id_strings, {[], []}, fn id_str, {us, is} ->
      id_str = to_string(id_str)

      case Integer.parse(id_str) do
        {int_id, ""} -> {us, [int_id | is]}
        _ -> {[id_str | us], is}
      end
    end)
  end
end
