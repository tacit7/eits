defmodule EyeInTheSky.Scheduler.IdleTicketNudger do
  @moduledoc """
  Periodically nudges idle sessions that still own open tasks.

  The worker sends a DM through `DMDelivery`, which means app-managed sessions
  can be resumed while terminal-owned sessions receive durable inbox messages
  without starting an app worker.
  """

  use GenServer

  require Logger

  alias EyeInTheSky.Messages
  alias EyeInTheSky.Messaging.DMDelivery
  alias EyeInTheSky.Sessions
  alias EyeInTheSky.Tasks

  @default_interval_ms :timer.minutes(5)
  @default_idle_age_seconds 5 * 60
  @default_cooldown_seconds 30 * 60
  @default_row_limit 500

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  def run_once_for_testing(opts \\ []) do
    run_once(%{attempts: %{}}, opts)
  end

  @impl GenServer
  def init(opts) do
    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)

    state = %{
      interval_ms: interval_ms,
      idle_age_seconds: Keyword.get(opts, :idle_age_seconds, @default_idle_age_seconds),
      cooldown_seconds: Keyword.get(opts, :cooldown_seconds, @default_cooldown_seconds),
      row_limit: Keyword.get(opts, :row_limit, @default_row_limit),
      attempts: %{}
    }

    Process.send_after(self(), :nudge_idle_tickets, 1_000)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:nudge_idle_tickets, state) do
    {state, stats} =
      run_once(state,
        idle_age_seconds: state.idle_age_seconds,
        cooldown_seconds: state.cooldown_seconds,
        row_limit: state.row_limit
      )

    if stats.sent > 0 do
      Logger.info("IdleTicketNudger sent #{stats.sent} ticket update nudge(s)")
    end

    Process.send_after(self(), :nudge_idle_tickets, state.interval_ms)
    {:noreply, state}
  end

  defp run_once(state, opts) do
    idle_age_seconds = Keyword.get(opts, :idle_age_seconds, @default_idle_age_seconds)
    cooldown_seconds = Keyword.get(opts, :cooldown_seconds, @default_cooldown_seconds)
    row_limit = Keyword.get(opts, :row_limit, @default_row_limit)
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -idle_age_seconds, :second)
    from_session_id = Sessions.ensure_web_ui_session()
    from_session = Sessions.get_session!(from_session_id)

    candidates = Tasks.list_open_tasks_for_idle_sessions(cutoff, row_limit: row_limit)

    {attempts, stats} =
      Enum.reduce(
        candidates,
        {Map.get(state, :attempts, %{}), %{sent: 0, skipped: 0, failed: 0}},
        fn candidate, {attempts, stats} ->
          task_ids = Enum.map(candidate.tasks, & &1.id)
          key = {candidate.session.id, task_ids}
          body = nudge_body(from_session, candidate.tasks)

          cond do
            recently_attempted?(attempts, key, now, cooldown_seconds) ->
              {attempts, %{stats | skipped: stats.skipped + 1}}

            recent_message?(candidate.session.id, body, cooldown_seconds) ->
              {Map.put(attempts, key, now), %{stats | skipped: stats.skipped + 1}}

            true ->
              metadata = %{
                source: "idle_ticket_nudger",
                response_required: false,
                task_ids: task_ids,
                session_uuid: candidate.session.uuid
              }

              case DMDelivery.deliver_or_persist(
                     candidate.session.id,
                     from_session.id,
                     body,
                     metadata
                   ) do
                {:ok, _message} ->
                  {Map.put(attempts, key, now), %{stats | sent: stats.sent + 1}}

                {:error, reason} ->
                  Logger.warning(
                    "IdleTicketNudger failed for session_id=#{candidate.session.id}: #{inspect(reason)}"
                  )

                  {Map.put(attempts, key, now), %{stats | failed: stats.failed + 1}}
              end
          end
        end
      )

    {Map.put(state, :attempts, prune_attempts(attempts, now, cooldown_seconds)), stats}
  rescue
    DBConnection.ConnectionError ->
      Logger.warning("IdleTicketNudger: DB unavailable, skipping")
      {state, %{sent: 0, skipped: 0, failed: 0}}
  end

  defp nudge_body(from_session, tasks) do
    task_lines =
      tasks
      |> Enum.take(10)
      |> Enum.map_join("\n", fn task -> "- ##{task.id}: #{task.title}" end)

    hidden_count = max(length(tasks) - 10, 0)

    more =
      if hidden_count > 0 do
        "\n- ...and #{hidden_count} more open ticket(s)"
      else
        ""
      end

    """
    DM from:EITS Scheduler (session:#{from_session.uuid}) You are idle with open ticket(s) assigned to this session:

    #{task_lines}#{more}

    Please review the ticket(s) and update status or add notes if applicable.
    """
    |> String.trim()
  end

  defp recent_message?(session_id, body, cooldown_seconds) do
    not is_nil(Messages.find_recent_dm(session_id, body, seconds: cooldown_seconds))
  end

  defp recently_attempted?(attempts, key, now, cooldown_seconds) do
    case Map.get(attempts, key) do
      nil -> false
      last_attempted_at -> DateTime.diff(now, last_attempted_at, :second) < cooldown_seconds
    end
  end

  defp prune_attempts(attempts, now, cooldown_seconds) do
    Map.reject(attempts, fn {_key, last_attempted_at} ->
      DateTime.diff(now, last_attempted_at, :second) >= cooldown_seconds
    end)
  end
end
