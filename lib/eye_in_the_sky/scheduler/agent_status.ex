defmodule EyeInTheSky.Scheduler.AgentStatus do
  @moduledoc """
  GenServer-based scheduler that periodically marks agents as stale, waiting, or unknown.

  Runs every 5 minutes to update agent status based on activity:
  - stale: inactive for more than 1 hour
  - waiting: active but created less than 1 hour ago
  - unknown: more than 1 day old without activity
  """

  use GenServer

  import Ecto.Query

  require Logger

  alias EyeInTheSky.{Agents, Events, Repo, Sessions}
  alias EyeInTheSky.Agents.Agent
  alias EyeInTheSky.Sessions.Session
  alias EyeInTheSky.Tasks.Task

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

    # Partition agents by desired new status in memory, then bulk-update each group.
    # Replaces N individual Repo.update calls with at most 3 Repo.update_all calls.
    {unknown, stale, idle} =
      Enum.reduce(agents, {[], [], []}, fn agent, {u, s, i} ->
        case desired_agent_status(agent, now) do
          "unknown" -> {[agent | u], s, i}
          "stale" -> {u, [agent | s], i}
          "idle" -> {u, s, [agent | i]}
          :skip -> {u, s, i}
        end
      end)

    bulk_update_agent_status(unknown, "unknown")
    bulk_update_agent_status(stale, "stale")
    bulk_update_agent_status(idle, "idle")

    total = length(unknown) + length(stale) + length(idle)

    Logger.debug(
      "Agent status update completed: #{length(agents)} agents checked, #{total} updated"
    )
  rescue
    DBConnection.ConnectionError -> Logger.warning("mark_stale_agents: DB unavailable, skipping")
  end

  defp desired_agent_status(agent, now) do
    cond do
      # Unknown: no activity in over 1 day
      too_old?(agent.last_activity_at, now) -> "unknown"
      # Stale: inactive for more than 1 hour
      stale?(agent.last_activity_at, now) -> "stale"
      # Idle: created less than 1 hour ago
      waiting?(agent.created_at, now) -> "idle"
      true -> :skip
    end
  end

  # Single bulk UPDATE per status group + per-agent PubSub broadcast.
  defp bulk_update_agent_status([], _status), do: :ok

  defp bulk_update_agent_status(agents, status) do
    ids = Enum.map(agents, & &1.id)
    Repo.update_all(from(a in Agent, where: a.id in ^ids), set: [status: status])
    Enum.each(agents, fn agent -> Events.agent_updated(%{agent | status: status}) end)
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

    # Preload agents in one batch — eliminates one get_agent/1 SELECT per idle session.
    idle_sessions =
      cutoff
      |> Sessions.list_idle_sessions_older_than()
      |> Repo.preload(:agent)

    # H1 fix: one grouped query replaces N individual active_task_count_for_session SELECTs.
    session_ids = Enum.map(idle_sessions, & &1.id)
    active_task_session_ids = bulk_sessions_with_active_tasks(session_ids)

    archived_count =
      idle_sessions
      |> Enum.reject(&MapSet.member?(active_task_session_ids, &1.id))
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

  # Returns a MapSet of session IDs that have at least one active (non-Done, non-archived) task.
  # One grouped query replaces N individual active_task_count_for_session SELECTs.
  # state_id 3 = Done (see workflow_states table).
  defp bulk_sessions_with_active_tasks([]), do: MapSet.new()

  defp bulk_sessions_with_active_tasks(session_ids) do
    from(ts in "task_sessions",
      join: t in Task,
      on: t.id == ts.task_id,
      where: ts.session_id in ^session_ids,
      where: t.state_id != 3 and t.archived == false,
      distinct: true,
      select: ts.session_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  # Sessions stuck in 'working' with no heartbeat for >30 minutes are zombies.
  # Their AgentWorker died without firing on_sdk_errored or on_session_failed.
  # Sweep them to 'failed' so the UI reflects reality.
  # Also mark the linked agent as failed to ensure UI status filters are correct.
  defp sweep_zombie_sessions do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -@thirty_minutes, :second)

    # Join agents upfront — eliminates one get_agent/1 SELECT per zombie session.
    zombies =
      from(s in Session,
        left_join: a in Agent,
        on: a.id == s.agent_id,
        where: s.status == "working",
        where:
          (not is_nil(s.last_activity_at) and s.last_activity_at < ^cutoff) or
            (is_nil(s.last_activity_at) and not is_nil(s.started_at) and s.started_at < ^cutoff),
        preload: [agent: a]
      )
      |> Repo.all()

    if zombies == [] do
      :ok
    else
      zombie_ids = Enum.map(zombies, & &1.id)
      agent_ids = zombies |> Enum.map(& &1.agent_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      # H2 fix: single Repo.update_all replaces N individual Sessions.update_session calls.
      # returning: [:id, :uuid] gives us enough to log and broadcast; no second SELECT needed.
      {_count, updated_sessions} =
        Repo.update_all(
          from(s in Session, where: s.id in ^zombie_ids),
          [set: [status: "failed", status_reason: "zombie_swept", updated_at: now]],
          returning: [:id, :uuid]
        )

      Enum.each(updated_sessions, fn s ->
        Logger.warning("Swept zombie session id=#{s.id} uuid=#{s.uuid} (stuck in working)")
        Events.session_status(s.id, "failed")
      end)

      # H2 fix: single Repo.update_all replaces M individual Agents.update_agent calls.
      if agent_ids != [] do
        Repo.update_all(
          from(a in Agent, where: a.id in ^agent_ids),
          set: [status: "failed", updated_at: now]
        )
      end

      Logger.info("Zombie sweep: marked #{length(zombies)} sessions as failed")
    end
  rescue
    DBConnection.ConnectionError ->
      Logger.warning("sweep_zombie_sessions: DB unavailable, skipping")
  end

  defp archive_session_and_agent(session, now) do
    Sessions.update_session(session, %{archived_at: now, status: "archived"})

    # session.agent is preloaded in archive_dead_idle_sessions/0 — no extra SELECT needed.
    if session.agent do
      Agents.archive_agent(session.agent, now)
    end
  end
end
