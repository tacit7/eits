defmodule EyeInTheSky.ScheduledJobs.CronPreview do
  @moduledoc """
  Generates human-readable descriptions of cron expressions.

  Examples:
    "0 9 * * 1-5" -> "Runs Monday-Friday at 9:00 AM"
    "*/5 * * * *" -> "Runs every 5 minutes"
    "0 0 1 * *" -> "Runs on the 1st of each month at 12:00 AM"
  """

  def preview(cron_expression) when is_binary(cron_expression) do
    case Crontab.CronExpression.Parser.parse(cron_expression) do
      {:ok, cron} -> build_description(cron)
      {:error, _} -> nil
    end
  end

  def preview(_), do: nil

  defp build_description(cron) do
    minute = cron.minute
    hour = cron.hour
    day = cron.day
    month = cron.month
    weekday = cron.weekday

    # crontab 1.2.0 represents all fields as lists of values/tuples:
    #   :*  → [:*]
    #   5   → [5]
    #   */N → [{:/, :*, N}]
    #   1-5 → [{:-, 1, 5}]
    case {minute, hour, day, month, weekday} do
      # Every minute: * * * * *
      {[:*], [:*], [:*], [:*], [:*]} ->
        "Runs every minute"

      # Every N minutes: */N * * * *
      {[{:/, :*, step}], [:*], [:*], [:*], [:*]} ->
        "Runs every #{step} minute#{if step == 1, do: "", else: "s"}"

      # Every hour at minute 0: 0 * * * *
      {[0], [:*], [:*], [:*], [:*]} ->
        "Runs every hour"

      # Specific time on specific days of week: M H * * DAYS
      {[min], [hour_val], [:*], [:*], weekday_list}
      when is_integer(min) and is_integer(hour_val) and weekday_list != [:*] ->
        time_str = format_time(min, hour_val)
        day_str = format_weekday_range(weekday_list)
        "Runs #{day_str} at #{time_str}"

      # Specific time every day: M H * * *
      {[min], [hour_val], [:*], [:*], [:*]} when is_integer(min) and is_integer(hour_val) ->
        time_str = format_time(min, hour_val)
        "Runs daily at #{time_str}"

      # Specific day of month and time: M H D * *
      {[min], [hour_val], [day_num], [:*], [:*]}
      when is_integer(min) and is_integer(hour_val) and is_integer(day_num) ->
        time_str = format_time(min, hour_val)
        "Runs on the #{ordinal(day_num)} of each month at #{time_str}"

      _ ->
        nil
    end
  end

  defp format_time(minute, hour) do
    hour_12 = rem(hour, 12)
    hour_12 = if hour_12 == 0, do: 12, else: hour_12
    meridiem = if hour < 12, do: "AM", else: "PM"
    "#{pad(hour_12)}:#{pad(minute)} #{meridiem}"
  end

  defp format_weekday_range(weekday_list) when is_list(weekday_list) do
    day_names =
      weekday_list
      |> Enum.flat_map(fn
        {:-, f, l} -> Enum.map(f..l, &weekday_name/1)
        d when is_integer(d) -> [weekday_name(d)]
        _ -> []
      end)
      |> Enum.uniq()

    case day_names do
      [single] ->
        single

      names ->
        if length(names) == 5 and "Monday" in names and "Friday" in names do
          "Monday-Friday"
        else
          Enum.join(names, ", ")
        end
    end
  end

  defp format_weekday_range(_), do: nil

  defp weekday_name(0), do: "Sunday"
  defp weekday_name(1), do: "Monday"
  defp weekday_name(2), do: "Tuesday"
  defp weekday_name(3), do: "Wednesday"
  defp weekday_name(4), do: "Thursday"
  defp weekday_name(5), do: "Friday"
  defp weekday_name(6), do: "Saturday"
  defp weekday_name(7), do: "Sunday"

  defp ordinal(n) when n in [1, 21, 31], do: "#{n}st"
  defp ordinal(n) when n in [2, 22], do: "#{n}nd"
  defp ordinal(n) when n in [3, 23], do: "#{n}rd"
  defp ordinal(n), do: "#{n}th"

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"
end
