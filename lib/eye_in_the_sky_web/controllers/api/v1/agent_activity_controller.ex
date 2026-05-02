defmodule EyeInTheSkyWeb.Api.V1.AgentActivityController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_duration: 1]

  alias EyeInTheSky.Agents
  alias EyeInTheSky.Agents.Activity

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
              tasks = Activity.fetch_tasks(agent.id, window_start)
              commits = Activity.fetch_commits(agent.id, window_start)
              sessions = Activity.fetch_sessions(agent.id, window_start)

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
end
