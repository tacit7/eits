defmodule EyeInTheSkyWeb.Tasks.Poller do
  @moduledoc """
  GenServer that polls for task changes and broadcasts via PubSub.
  Catches external writes from Go MCP i-todo commands and other agents.
  """

  use GenServer
  require Logger
  alias EyeInTheSkyWeb.Repo

  @poll_interval 2_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    last_updated = get_max_updated_at()
    last_count = get_task_count()
    schedule_poll()
    {:ok, %{last_updated: last_updated, last_count: last_count}}
  end

  @impl true
  def handle_info(:poll, state) do
    current_updated = get_max_updated_at()
    current_count = get_task_count()

    changed? = current_updated != state.last_updated or current_count != state.last_count

    if changed? do
      Logger.debug("Tasks.Poller: detected task changes, broadcasting")
      broadcast_tasks_changed()
    end

    schedule_poll()
    {:noreply, %{state | last_updated: current_updated, last_count: current_count}}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp get_max_updated_at do
    case Repo.query("SELECT MAX(updated_at) FROM tasks") do
      {:ok, %{rows: [[val]]}} -> val
      _ -> nil
    end
  end

  defp get_task_count do
    case Repo.query("SELECT COUNT(*) FROM tasks") do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end

  defp broadcast_tasks_changed do
    EyeInTheSkyWeb.Events.tasks_changed()
  end
end
