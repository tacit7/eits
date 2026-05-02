defmodule EyeInTheSky.Tasks.Poller do
  @moduledoc """
  GenServer that polls for task changes and broadcasts via PubSub.
  Catches external task writes from spawned agents and other sources.
  """

  use GenServer
  require Logger
  alias EyeInTheSky.Repo

  # Reduced from 2s to 5s — two queries merged into one, cutting DB round-trips by 2.5x.
  # At 2s with two separate queries, this was generating ~1.24M calls each in pg_stat_statements.
  @poll_interval 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {last_updated, last_count} = get_task_snapshot()
    schedule_poll()
    {:ok, %{last_updated: last_updated, last_count: last_count}}
  end

  @impl true
  def handle_info(:poll, state) do
    {current_updated, current_count} = get_task_snapshot()

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

  # Single round-trip replaces two separate MAX + COUNT queries.
  # tasks_updated_at_index (updated_at DESC) turns the MAX into a 1-block backward scan.
  defp get_task_snapshot do
    case Repo.query("SELECT MAX(updated_at), COUNT(*) FROM tasks") do
      {:ok, %{rows: [[max_updated, count]]}} -> {max_updated, count}
      _ -> {nil, 0}
    end
  end

  defp broadcast_tasks_changed do
    EyeInTheSky.Events.tasks_changed()
  end
end
