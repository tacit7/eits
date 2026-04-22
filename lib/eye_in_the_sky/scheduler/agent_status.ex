defmodule EyeInTheSky.Scheduler.AgentStatus do
  @moduledoc """
  GenServer-based scheduler that periodically marks agents as stale, waiting, or unknown.

  Runs every 5 minutes to update agent status based on activity:
  - stale: inactive for more than 1 hour
  - waiting: active but created less than 1 hour ago
  - unknown: more than 1 day old without activity
  """

  use GenServer

  require Logger

  alias EyeInTheSky.{Agents, Events, Repo, Sessions, Tasks}
  alias EyeInTheSky.Sessions.Session

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000
  @one_hour_ago 60 * 60
  @one_day_ago 24 * 60 * 60
  @thirty_minutes 30 * 60

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc false
  def sweep_zombie_sessions_for_testing do
    sweep_zombie_sessions()
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
    sweep_zombie_sessions()
    archive_dead_idle_sessions()
    # Schedule the next run
    Process.send_after(self(), :mark_stale, @interval)
    {:noreply, state}
  end

  defp mark_stale_agents do
    now = DateTime.utc_now()

    agents = Agents.list_agents_pending_status_check()

    Enum.each(agents, fn agent -> update_agent_status(agent, now) end)

    Logger.debug("Agent status update completed: #{length(agents)} agents checked")
  rescue
    DBConnection.ConnectionError -> Logger.warning("mark_stale_agents: DB unavailable, skipping")
  end

  defp update_agent_status(agent, now) do
    cond do
      # Unknown: no activity in over 1 day
      too_old?(agent.last_activity_at, now) ->
        Agents.update_agent(agent, %{status: "unknown"})

      # Stale: inactive for more than 1 hour
      stale?(agent.last_activity_at, now) ->
        Agents.update_agent(agent, %{status: "stale"})

      # Idle: active but created less than 1 hour ago
      waiting?(agent.created_at, now) ->
        Agents.update_agent(agent, %{status: "idle"})

      # Active: recent activity or just created
      true ->
        :skip
    end
  end

  defp too_old?(nil, _now), do: false

  defp too_old?(%DateTime{} = last_activity_at, now) do
    DateTime.diff(now, last_activity_at) > @one_day_ago
  end

  defp stale?(nil, _now), do: false

  defp stale?(%DateTime{} = last_activity_at, now) do
    DateTime.diff(now, last_activity_at) > @one_hour_ago
  end

  defp waiting?(nil, _now), do: false

  defp waiting?(%DateTime{} = created_at, now) do
    DateTime.diff(now, created_at) < @one_hour_ago
  end

  # Archive sessions that are idle, older than 30 min, and have no active tasks.
  defp archive_dead_idle_sessions do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -@thirty_minutes, :second)

    idle_sessions = Sessions.list_idle_sessions_older_than(cutoff)

    archived_count =
      idle_sessions
      |> Enum.filter(&no_active_tasks?/1)
      |> Enum.reduce(0, fn session, count ->
        archive_session_and_agent(session, now)
        count + 1
      end)

    if archived_count > 0 do
      Logger.info("Auto-archived #{archived_count} dead idle session(s)")
    end
  rescue
    DBConnection.ConnectionError ->
      Logger.warning("archive_dead_idle_sessions: DB unavailable, skipping")
  end

  # Sessions stuck in 'working' with no heartbeat for >30 minutes are zombies.
  # Their AgentWorker died without firing on_sdk_errored or on_session_failed.
  # Sweep them to 'failed' so the UI reflects reality.
  defp sweep_zombie_sessions do
    import Ecto.Query

    cutoff = DateTime.utc_now() |> DateTime.add(-@thirty_minutes, :second)

    zombies =
      from(s in Session,
        where: s.status == "working",
        where: is_nil(s.last_activity_at) or s.last_activity_at < ^cutoff,
        select: s
      )
      |> Repo.all()

    Enum.each(zombies, fn session ->
      case Sessions.update_session(session, %{status: "failed", status_reason: "zombie_swept"}) do
        {:ok, updated} ->
          Logger.warning("Swept zombie session id=#{session.id} uuid=#{session.uuid} (stuck in working)")
          Events.session_status(session.id, updated.status)

        {:error, reason} ->
          Logger.warning("Failed to sweep zombie session id=#{session.id}: #{inspect(reason)}")
      end
    end)

    if length(zombies) > 0, do: Logger.info("Zombie sweep: marked #{length(zombies)} sessions as failed")
  rescue
    DBConnection.ConnectionError -> Logger.warning("sweep_zombie_sessions: DB unavailable, skipping")
  end

  # Returns true when a session has no linked tasks, or all linked tasks are done/archived.
  # state_id 3 = Done (see workflow_states table)
  defp no_active_tasks?(session) do
    Tasks.active_task_count_for_session(session.id) == 0
  end

  defp archive_session_and_agent(session, now) do
    # Archive the session
    Sessions.update_session(session, %{archived_at: now, status: "archived"})

    # Archive the associated agent if present
    if session.agent_id do
      case Agents.get_agent(session.agent_id) do
        {:ok, agent} -> Agents.archive_agent(agent, now)
        {:error, :not_found} -> :ok
      end
    end
  end
end
