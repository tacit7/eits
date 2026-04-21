defmodule EyeInTheSky.TaskSessions do
  @moduledoc """
  The TaskSessions context for managing task-session relationships.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Tasks.Task

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
    Repo.exists?(
      from ts in "task_sessions",
        where: ts.task_id == ^task_id and ts.session_id == ^session_id
    )
  end

  def task_linked_to_session?(_, _), do: false

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

  @doc """
  Atomically transfers executor ownership of a task to a new session.
  Removes all existing task_sessions entries for the task and inserts the new one.
  Used by claim to ensure the stop hook fires on the session actually executing the task.
  """
  def transfer_session_ownership(task_id, new_session_id)
      when is_integer(task_id) and is_integer(new_session_id) do
    Repo.transaction(fn ->
      from(ts in "task_sessions", where: ts.task_id == ^task_id)
      |> Repo.delete_all()

      Repo.insert_all(
        "task_sessions",
        [%{task_id: task_id, session_id: new_session_id}],
        on_conflict: :nothing
      )
    end)

    {:ok, new_session_id}
  end

  @doc """
  Returns the count of active (not done, not archived) tasks linked to the given session.
  Used by the scheduler to determine if an idle session can be auto-archived.
  State ID 3 = Done.
  """
  def active_task_count_for_session(session_id) do
    from(ts in "task_sessions",
      join: t in Task,
      on: t.id == ts.task_id,
      where: ts.session_id == ^session_id,
      where: t.state_id != 3 and t.archived == false,
      select: count()
    )
    |> Repo.one()
  end
end
