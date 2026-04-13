defmodule EyeInTheSky.ScheduledJobs.CronParser do
  @moduledoc false

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
    end
  end

  defp next_cron_run_at(schedule_value, utc_now, timezone) do
    case Parser.parse(schedule_value) do
      {:ok, parsed} ->
        local_now = utc_to_local(utc_now, timezone)

        case Crontab.Scheduler.get_next_run_date(parsed, local_now) do
          {:ok, next_local} -> local_to_utc(next_local, timezone) |> DateTime.from_naive!("Etc/UTC")
          _ -> nil
        end

      {:error, _} ->
        nil
    end
  end

  defp utc_to_local(naive_utc, "Etc/UTC"), do: naive_utc

  defp utc_to_local(naive_utc, timezone) do
    naive_utc
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.shift_zone!(timezone)
    |> DateTime.to_naive()
  end

  defp local_to_utc(naive_local, "Etc/UTC"), do: naive_local

  defp local_to_utc(naive_local, timezone) do
    naive_local
    |> DateTime.from_naive!(timezone)
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_naive()
  end
end
