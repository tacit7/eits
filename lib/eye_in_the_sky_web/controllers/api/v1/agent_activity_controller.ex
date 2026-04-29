defmodule EyeInTheSkyWeb.Api.V1.AgentActivityController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Repo
  import Ecto.Query

  def activity(conn, %{"uuid" => agent_uuid, "since" => since_str}) do
    with {:ok, since_dt, _} <- DateTime.from_iso8601(since_str),
         {:ok, agent} <- Agents.get_agent_by_uuid(agent_uuid) do
      tasks = fetch_tasks(agent.id, since_dt)
      commits = fetch_commits(agent.id, since_dt)
      sessions = fetch_sessions(agent.id, since_dt)

      json(conn, %{
        success: true,
        agent_uuid: agent_uuid,
        since: since_str,
        tasks: tasks,
        commits: commits,
        sessions: sessions,
        summary: %{
          task_count: length(tasks),
          commit_count: length(commits),
          session_count: length(sessions)
        }
      })
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Agent not found"})

      {:error, reason} when is_atom(reason) ->
        conn |> put_status(:bad_request) |> json(%{error: "Invalid since datetime: #{reason}"})
    end
  end

  def activity(conn, params) when not is_map_key(params, "uuid") do
    conn |> put_status(:bad_request) |> json(%{error: "uuid param required"})
  end

  def activity(conn, params) when not is_map_key(params, "since") do
    conn |> put_status(:bad_request) |> json(%{error: "since param required"})
  end

  defp fetch_tasks(agent_id, since_dt) do
    from(t in "tasks",
      where: t.agent_id == ^agent_id,
      where: t.created_at >= ^since_dt or t.updated_at >= ^since_dt,
      left_join: ws in "workflow_states",
      on: ws.id == t.state_id,
      select: %{
        id: t.id,
        title: t.title,
        state: ws.name,
        state_id: t.state_id
      }
    )
    |> Repo.all()
  end

  defp fetch_commits(agent_id, since_dt) do
    from(c in "commits",
      join: s in "sessions",
      on: s.id == c.session_id,
      where: s.agent_id == ^agent_id,
      where: c.created_at >= ^since_dt,
      select: %{
        hash: c.commit_hash,
        message: c.commit_message
      }
    )
    |> Repo.all()
  end

  defp fetch_sessions(agent_id, since_dt) do
    from(s in "sessions",
      where: s.agent_id == ^agent_id,
      where: s.last_activity_at >= ^since_dt or s.inserted_at >= ^since_dt,
      select: %{
        uuid: s.uuid,
        name: s.name,
        status: s.status
      }
    )
    |> Repo.all()
  end
end
