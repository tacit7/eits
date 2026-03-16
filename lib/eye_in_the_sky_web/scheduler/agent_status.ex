defmodule EyeInTheSkyWeb.Scheduler.AgentStatus do
  @moduledoc """
  GenServer-based scheduler that periodically marks agents as stale, waiting, or unknown.

  Runs every 5 minutes to update agent status based on activity:
  - stale: inactive for more than 1 hour
  - waiting: active but created less than 1 hour ago
  - unknown: more than 1 day old without activity
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias EyeInTheSkyWeb.{Agents, Repo, Sessions}
  alias Agents.Agent
  alias Sessions.Session

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000
  @one_hour_ago 60 * 60
  @one_day_ago 24 * 60 * 60
  @thirty_minutes 30 * 60

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl GenServer
  def init(nil) do
    # Schedule the first run after 1 second to let the app start up
    Process.send_after(self(), :mark_stale, 1000)
    {:ok, nil}
  end

  @impl GenServer
  def handle_info(:mark_stale, state) do
    mark_stale_agents()
    archive_dead_idle_sessions()
    # Schedule the next run
    Process.send_after(self(), :mark_stale, @interval)
    {:noreply, state}
  end

  defp parse_iso8601(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.to_naive(dt)
      _ -> nil
    end
  end

  defp parse_iso8601(_), do: nil

  defp mark_stale_agents do
    try do
      now = NaiveDateTime.utc_now()

      # Get all agents except completed/failed
      agents =
        from(a in Agent,
          where: a.status not in ["completed", "failed"]
        )
        |> Repo.all()

      Enum.each(agents, fn agent -> update_agent_status(agent, now) end)

      Logger.debug("Agent status update completed: #{length(agents)} agents checked")
    rescue
      e ->
        Logger.error("Error marking stale agents: #{inspect(e)}")
    end
  end

  defp update_agent_status(agent, now) do
    cond do
      # Unknown: no activity in over 1 day
      is_too_old(agent.last_activity_at, now) ->
        Agents.update_agent_status(agent, "unknown")

      # Stale: inactive for more than 1 hour
      is_stale(agent.last_activity_at, now) ->
        Agents.update_agent_status(agent, "stale")

      # Idle: active but created less than 1 hour ago
      is_waiting(agent.created_at, now) ->
        Agents.update_agent_status(agent, "idle")

      # Active: recent activity or just created
      true ->
        :skip
    end
  end

  defp is_too_old(last_activity_at, now) do
    case parse_iso8601(last_activity_at) do
      nil -> false
      dt -> NaiveDateTime.diff(now, dt) > @one_day_ago
    end
  end

  defp is_stale(last_activity_at, now) do
    case parse_iso8601(last_activity_at) do
      nil -> false
      dt -> NaiveDateTime.diff(now, dt) > @one_hour_ago
    end
  end

  defp is_waiting(created_at, _now) when is_nil(created_at) do
    false
  end

  defp is_waiting(created_at, now) do
    seconds_since = NaiveDateTime.diff(now, created_at)
    seconds_since < @one_hour_ago
  end

  # Archive sessions that are idle, older than 30 min, and have no active tasks.
  defp archive_dead_idle_sessions do
    try do
      now = DateTime.utc_now()
      cutoff = DateTime.add(now, -@thirty_minutes, :second) |> DateTime.to_iso8601()
      now_iso = DateTime.to_iso8601(now)

      # Sessions that are idle, not archived, and started more than 30 min ago
      idle_sessions =
        from(s in Session,
          where: s.status == "idle",
          where: is_nil(s.archived_at),
          where: not is_nil(s.started_at),
          where: s.started_at < ^cutoff
        )
        |> Repo.all()

      archived_count =
        idle_sessions
        |> Enum.filter(&no_active_tasks?/1)
        |> Enum.reduce(0, fn session, count ->
          archive_session_and_agent(session, now_iso)
          count + 1
        end)

      if archived_count > 0 do
        Logger.info("Auto-archived #{archived_count} dead idle session(s)")
      end
    rescue
      e ->
        Logger.error("Error archiving dead idle sessions: #{inspect(e)}")
    end
  end

  # Returns true when a session has no linked tasks, or all linked tasks are done/archived.
  # state_id 3 = Done (see workflow_states table)
  defp no_active_tasks?(session) do
    active_task_count =
      from(ts in "task_sessions",
        join: t in EyeInTheSkyWeb.Tasks.Task,
        on: t.id == ts.task_id,
        where: ts.session_id == ^session.id,
        where: t.state_id != 3 and t.archived == false,
        select: count()
      )
      |> Repo.one()

    active_task_count == 0
  end

  defp archive_session_and_agent(session, now_iso) do
    # Archive the session
    Sessions.update_session(session, %{archived_at: now_iso, status: "archived"})

    # Archive the associated agent if present
    if session.agent_id do
      case Repo.get(Agent, session.agent_id) do
        nil -> :ok
        agent ->
          agent
          |> Ecto.Changeset.change(%{archived_at: now_iso})
          |> Repo.update()
      end
    end
  end
end
