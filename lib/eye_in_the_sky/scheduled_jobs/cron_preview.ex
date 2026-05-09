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

    case {minute, hour, day, month, weekday} do
      # Every N minutes
      {%Crontab.CronExpression.Step{step: step, range: 0..59}, :*, :*, :*, :*} ->
        "Runs every #{step} minute#{if step == 1, do: "", else: "s"}"

      # Every hour
      {0, :*, :*, :*, :*} ->
        "Runs every hour"

      # Specific time every day
      {min, %Crontab.CronExpression.Step{step: 1, range: 0..23}, :*, :*, :*} when is_integer(min) ->
        time_str = format_time(min, 0)
        "Runs daily at #{time_str}"

      # Specific time on specific days of week
      {min, hour, :*, :*, weekday_range} when is_integer(min) and is_integer(hour) and
                                               weekday_range != :* ->
        time_str = format_time(min, hour)
        day_str = format_weekday_range(weekday_range)
        "Runs #{day_str} at #{time_str}"

      # Specific day of month and time
      {min, hour, day_num, :*, :*} when is_integer(min) and is_integer(hour) and is_integer(day_num) ->
        time_str = format_time(min, hour)
        "Runs on the #{ordinal(day_num)} of each month at #{time_str}"

      # Every minute
      {0, :*, :*, :*, :*} ->
        "Runs every minute"

      # Fallback: show the raw expression
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

  defp format_weekday_range(range) when is_list(range) do
    days = Enum.map(range, &weekday_name/1) |> Enum.uniq()

    case days do
      [single] ->
        single

      days ->
        {first, last} = {List.first(days), List.last(days)}

        if Enum.count(days) == 5 and
             Enum.member?(days, "Monday") and Enum.member?(days, "Friday") do
          "Monday-Friday"
        else
          Enum.join(days, ", ")
        end
    end
  end

  defp format_weekday_range(range) do
    case range do
      %Crontab.CronExpression.Range{first: f, last: l} ->
        first_day = weekday_name(f)
        last_day = weekday_name(l)
        "#{first_day}-#{last_day}"

      _ ->
        nil
    end
  end

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
