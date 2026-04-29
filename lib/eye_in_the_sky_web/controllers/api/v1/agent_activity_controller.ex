defmodule EyeInTheSkyWeb.Api.V1.AgentActivityController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import Ecto.Query
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_duration: 1]

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Commits.Commit
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Tasks.Task
  alias EyeInTheSky.Tasks.WorkflowState

  @doc """
  GET /api/v1/agents/activity?agent_uuid=<uuid>&since=<duration>

  Returns categorised 24h-style activity for one agent: tasks (done / in_review /
  in_progress / stale), commits, and sessions within the requested window.

  `since` accepts Nh / Nd / Nm duration strings (e.g. "24h", "7d", "30m") or a
  full ISO8601 timestamp. Defaults to "24h" when omitted.
  """
  def activity(conn, params) do
    agent_uuid = params["agent_uuid"]

    if is_nil(agent_uuid) or agent_uuid == "" do
      conn |> put_status(:bad_request) |> json(%{error: "agent_uuid param required"})
    else
      since_str = params["since"] || "24h"

      case parse_duration(since_str) do
        {:error, message} ->
          conn |> put_status(:bad_request) |> json(%{error: message})

        {:ok, window_start} ->
          case Agents.get_agent_by_uuid(agent_uuid) do
            {:error, :not_found} ->
              conn |> put_status(:not_found) |> json(%{error: "Agent not found"})

            {:ok, agent} ->
              tasks = fetch_tasks(agent.id, window_start)
              commits = fetch_commits(agent.id, window_start)
              sessions = fetch_sessions(agent.id, window_start)

              json(conn, %{
                success: true,
                agent_uuid: agent_uuid,
                since: since_str,
                window_start: DateTime.to_iso8601(window_start),
                tasks: tasks,
                commits: commits,
                sessions: sessions
              })
          end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Returns a map with four task buckets:
  #   done        — completed within the window
  #   in_review   — currently in review (state 4)
  #   in_progress — in progress (state 2) and touched within the window
  #   stale       — in progress (state 2) but NOT updated within the window
  #
  # Any To-Do tasks (state 1) that were touched within the window are surfaced
  # under in_progress so callers see all recent motion.
  defp fetch_tasks(agent_id, window_start) do
    done_id = WorkflowState.done_id()
    in_progress_id = WorkflowState.in_progress_id()
    in_review_id = WorkflowState.in_review_id()

    # Fetch tasks that are either:
    #  a) non-done (always relevant for standup)
    #  b) done and updated within the window
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
        order_by: [desc: t.updated_at]
      )
      |> Repo.all()

    done =
      tasks
      |> Enum.filter(&(&1.state_id == done_id))
      |> Enum.map(fn t ->
        %{
          id: t.id,
          title: t.title,
          completed_at: format_dt(t.completed_at)
        }
      end)

    in_review =
      tasks
      |> Enum.filter(&(&1.state_id == in_review_id))
      |> Enum.map(&format_active_task/1)

    # Split in-progress by whether they were touched within the window
    ip_tasks = Enum.filter(tasks, &(&1.state_id == in_progress_id))

    {in_progress, stale} =
      Enum.split_with(ip_tasks, fn t ->
        t.updated_at != nil and
          DateTime.compare(t.updated_at, window_start) != :lt
      end)

    %{
      done: done,
      in_review: Enum.map(in_review, & &1),
      in_progress: Enum.map(in_progress, &format_active_task/1),
      stale: Enum.map(stale, &format_active_task/1)
    }
  end

  defp format_active_task(t), do: %{id: t.id, title: t.title, updated_at: format_dt(t.updated_at)}

  defp fetch_commits(agent_id, window_start) do
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
      order_by: [desc: c.created_at]
    )
    |> Repo.all()
    |> Enum.map(fn c -> Map.update!(c, :inserted_at, &format_dt/1) end)
  end

  defp fetch_sessions(agent_id, window_start) do
    from(s in Session,
      where: s.agent_id == ^agent_id,
      where: s.last_activity_at >= ^window_start or s.inserted_at >= ^window_start,
      select: %{
        id: s.id,
        uuid: s.uuid,
        name: s.name,
        status: s.status
      },
      order_by: [desc: s.inserted_at]
    )
    |> Repo.all()
  end

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
end
