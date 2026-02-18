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

  alias EyeInTheSkyWeb.{Agents, Repo}
  alias Agents.Agent

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000
  @one_hour_ago 60 * 60
  @one_day_ago 24 * 60 * 60

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
    # Schedule the next run
    Process.send_after(self(), :mark_stale, @interval)
    {:noreply, state}
  end

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

  defp is_too_old(last_activity_at, _now) when is_nil(last_activity_at) do
    false
  end

  defp is_too_old(last_activity_at, now) do
    seconds_since = NaiveDateTime.diff(now, last_activity_at)
    seconds_since > @one_day_ago
  end

  defp is_stale(last_activity_at, _now) when is_nil(last_activity_at) do
    false
  end

  defp is_stale(last_activity_at, now) do
    seconds_since = NaiveDateTime.diff(now, last_activity_at)
    seconds_since > @one_hour_ago
  end

  defp is_waiting(created_at, _now) when is_nil(created_at) do
    false
  end

  defp is_waiting(created_at, now) do
    seconds_since = NaiveDateTime.diff(now, created_at)
    seconds_since < @one_hour_ago
  end
end
