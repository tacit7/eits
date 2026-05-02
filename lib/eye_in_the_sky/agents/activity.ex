defmodule EyeInTheSky.Agents.Activity do
  @moduledoc false

  import Ecto.Query

  alias EyeInTheSky.Commits.Commit
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Tasks.Task
  alias EyeInTheSky.Tasks.WorkflowState

  @doc """
  Returns task rows for the activity report, split into four buckets:
  done, in_review, in_progress, and stale.

  Tasks completed outside the window are excluded. Active tasks are always
  included; in_progress is split by whether updated_at falls within the window.
  """
  def fetch_tasks(agent_id, window_start) do
    done_id = WorkflowState.done_id()
    in_progress_id = WorkflowState.in_progress_id()
    in_review_id = WorkflowState.in_review_id()

    tasks =
      from(t in Task,
        where: t.agent_id == ^agent_id,
        where: t.archived == false,
        where:
          t.state_id != ^done_id or
            (t.state_id == ^done_id and t.updated_at >= ^window_start),
        select: %{
          id: t.id,
          title: t.title,
          state_id: t.state_id,
          completed_at: t.completed_at,
          updated_at: t.updated_at
        },
        order_by: [desc: t.updated_at],
        limit: 500
      )
      |> Repo.all()

    done =
      tasks
      |> Enum.filter(&(&1.state_id == done_id))
      |> Enum.map(fn t ->
        %{id: t.id, title: t.title, completed_at: format_dt(t.completed_at)}
      end)

    in_review =
      tasks
      |> Enum.filter(&(&1.state_id == in_review_id))
      |> Enum.map(&format_active_task/1)

    ip_tasks = Enum.filter(tasks, &(&1.state_id == in_progress_id))

    {in_progress, stale} =
      Enum.split_with(ip_tasks, fn t ->
        t.updated_at != nil and
          DateTime.compare(t.updated_at, window_start) != :lt
      end)

    %{
      done: done,
      in_review: in_review,
      in_progress: Enum.map(in_progress, &format_active_task/1),
      stale: Enum.map(stale, &format_active_task/1)
    }
  end

  @doc """
  Returns commits linked to the agent's sessions within the window.
  """
  def fetch_commits(agent_id, window_start) do
    from(c in Commit,
      join: s in Session,
      on: s.id == c.session_id,
      where: s.agent_id == ^agent_id,
      where: c.created_at >= ^window_start,
      select: %{
        hash: c.commit_hash,
        message: c.commit_message,
        session_id: c.session_id,
        inserted_at: c.created_at
      },
      order_by: [desc: c.created_at],
      limit: 500
    )
    |> Repo.all()
    |> Enum.map(fn c -> Map.update!(c, :inserted_at, &format_dt/1) end)
  end

  @doc """
  Returns sessions for the agent that had activity within the window.
  """
  def fetch_sessions(agent_id, window_start) do
    from(s in Session,
      where: s.agent_id == ^agent_id,
      where: s.last_activity_at >= ^window_start or s.inserted_at >= ^window_start,
      select: %{
        id: s.id,
        uuid: s.uuid,
        name: s.name,
        status: s.status
      },
      order_by: [desc: s.inserted_at],
      limit: 500
    )
    |> Repo.all()
  end

  defp format_active_task(t), do: %{id: t.id, title: t.title, updated_at: format_dt(t.updated_at)}

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
end
