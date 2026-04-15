defmodule EyeInTheSky.ScheduledJobs.CronParser do
  @moduledoc false

  require Logger

  alias Crontab.CronExpression.Parser
  alias EyeInTheSky.Utils.ToolHelpers

  @doc """
  Compute the next run DateTime for a job given its schedule type and value.

  `from` defaults to `NaiveDateTime.utc_now()` when nil.
  `timezone` defaults to `"Etc/UTC"`.
  """
  def compute_next_run_at(schedule_type, schedule_value, from \\ nil, timezone \\ "Etc/UTC") do
    utc_now = from || NaiveDateTime.utc_now()

    case schedule_type do
      "interval" ->
        seconds = ToolHelpers.parse_int(schedule_value) || 0

        if seconds > 0 do
          NaiveDateTime.add(utc_now, seconds) |> DateTime.from_naive!("Etc/UTC")
        else
          nil
        end

      "cron" ->
        next_cron_run_at(schedule_value, utc_now, timezone)

      _ ->
        nil
    end
  end

  defp next_cron_run_at(schedule_value, utc_now, timezone) do
    case Parser.parse(schedule_value) do
      {:ok, parsed} ->
        with {:ok, local_now} <- utc_to_local(utc_now, timezone),
             {:ok, next_local} <- Crontab.Scheduler.get_next_run_date(parsed, local_now),
             {:ok, next_utc_naive} <- local_to_utc(next_local, timezone),
             {:ok, next_utc} <- DateTime.from_naive(next_utc_naive, "Etc/UTC") do
          next_utc
        else
          {:error, :time_zone_not_found} ->
            Logger.warning(
              "CronParser: invalid timezone #{inspect(timezone)}, skipping next_run_at"
            )

            nil

          _ ->
            nil
        end

      {:error, _} ->
        nil
    end
  end

  defp utc_to_local(naive_utc, "Etc/UTC"), do: {:ok, naive_utc}

  defp utc_to_local(naive_utc, timezone) do
    case DateTime.from_naive(naive_utc, "Etc/UTC") do
      {:ok, dt} ->
        case DateTime.shift_zone(dt, timezone) do
          {:ok, shifted} -> {:ok, DateTime.to_naive(shifted)}
          error -> error
        end

      error ->
        error
    end
  end

  defp local_to_utc(naive_local, "Etc/UTC"), do: {:ok, naive_local}

  defp local_to_utc(naive_local, timezone) do
    case DateTime.from_naive(naive_local, timezone) do
      {:ok, dt} ->
        case DateTime.shift_zone(dt, "Etc/UTC") do
          {:ok, utc} -> {:ok, DateTime.to_naive(utc)}
          error -> error
        end

      error ->
        error
    end
  end
end
