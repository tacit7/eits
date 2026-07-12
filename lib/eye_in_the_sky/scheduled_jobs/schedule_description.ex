defmodule EyeInTheSky.ScheduledJobs.ScheduleDescription do
  @moduledoc """
  Single source of truth for turning a scheduled job's schedule into a terse,
  human-readable label. Replaces the former split between
  `EyeInTheSky.ScheduledJobs.CronPreview` (form preview) and
  `EyeInTheSkyWeb.Live.Shared.JobsFormatters.describe_cron/1` (jobs table), which
  had diverged in wording, coverage, and correctness.

  Two entry points share one description core:

    * `describe/1` — full schedule (interval OR cron). Always returns a usable
      string; falls back to the raw `schedule_value` for cron patterns it can't
      phrase, and `"?"` for unknown schedule types. Used by the jobs table/page.
    * `preview/1` — cron expression only. Validates with the real crontab parser
      and returns `nil` for anything invalid or unrecognized, so the create/edit
      form can hide the hint. Used by the job form drawer.

  Output style is terse (fits a narrow table column):

      "*/15 * * * *"  -> "Every 15m"
      "0 */4 * * *"   -> "Every 4h"
      "0 9 * * *"     -> "Daily at 9 AM"
      "30 14 * * *"   -> "Daily at 2:30 PM"
      "0 8 * * 1-5"   -> "Weekdays at 8 AM"
      "0 10 * * 0,6"  -> "Weekends at 10 AM"
      "0 9 15 * *"    -> "Day 15 at 9 AM"
      interval 2700   -> "Every 45m"
  """

  alias Crontab.CronExpression.Parser, as: CrontabParser
  alias EyeInTheSky.Utils.ToolHelpers

  @days_of_week %{
    0 => "Sun",
    1 => "Mon",
    2 => "Tue",
    3 => "Wed",
    4 => "Thu",
    5 => "Fri",
    6 => "Sat",
    7 => "Sun"
  }

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Describe any schedule. Never returns nil; falls back to the raw value for
  unrecognized cron and `"?"` for unknown schedule types.
  """
  def describe(%{schedule_type: "interval", schedule_value: val}), do: describe_interval(val)

  def describe(%{schedule_type: "cron", schedule_value: val}) do
    case analyze_cron(val) do
      {:ok, desc} -> desc
      :error -> val
    end
  end

  def describe(_), do: "?"

  @doc """
  Preview a cron expression for the form. Returns nil for invalid or
  unrecognized expressions so the caller can hide the hint.
  """
  def preview(expr) when is_binary(expr) do
    case analyze_cron(expr) do
      {:ok, desc} -> desc
      :error -> nil
    end
  end

  def preview(_), do: nil

  # ---------------------------------------------------------------------------
  # Interval
  # ---------------------------------------------------------------------------

  defp describe_interval(val) do
    case ToolHelpers.parse_int(val) do
      nil -> val
      s when s >= 3600 -> "Every #{div(s, 3600)}h"
      s when s >= 60 -> "Every #{div(s, 60)}m"
      s -> "Every #{s}s"
    end
  end

  # ---------------------------------------------------------------------------
  # Cron — returns {:ok, description} | :error
  # ---------------------------------------------------------------------------

  # Validates against the real crontab parser first — rejects out-of-range or
  # malformed fields (e.g. hour 99) that a naive split-and-parse would happily
  # mis-describe — then hand-parses the 5 fields into a phrase.
  defp analyze_cron(expr) when is_binary(expr) do
    with {:ok, _} <- CrontabParser.parse(expr),
         [min, hour, dom, mon, dow] <- String.split(String.trim(expr), ~r/\s+/) do
      describe_fields(min, hour, dom, mon, dow)
    else
      _ -> :error
    end
  end

  defp analyze_cron(_), do: :error

  defp describe_fields(min, hour, dom, mon, dow) do
    every_day? = dom == "*" and mon == "*" and dow == "*"
    day = day_label(dow, dom, mon)

    case frequency(min, hour) do
      # A pure frequency ("Every 15m", "Hourly") stands alone when it runs
      # every day. When day/month is restricted (e.g. "0 */4 * * 1-5"), the
      # frequency must combine with the day qualifier instead of being
      # dropped — the old fall-through-to-clock_time path silently discarded
      # it since clock_time can't parse a "*/4" step as a plain hour.
      freq when is_binary(freq) and every_day? ->
        {:ok, freq}

      freq when is_binary(freq) ->
        {:ok, combine_freq(freq, day)}

      _ ->
        combine(clock_time(min, hour), day)
    end
  end

  defp combine_freq(freq, nil), do: freq
  defp combine_freq(freq, day), do: "#{day}, #{freq}"

  # Recurring-frequency phrasings. Returns a string or nil.
  defp frequency("*", "*"), do: "Every minute"
  defp frequency("0", "*"), do: "Hourly"

  defp frequency("*/" <> step, "*") do
    if n = ToolHelpers.parse_int(step), do: "Every #{n}m", else: nil
  end

  defp frequency(min, "*/" <> step) do
    with n when not is_nil(n) <- ToolHelpers.parse_int(step),
         m when not is_nil(m) <- ToolHelpers.parse_int(min),
         true <- m == 0 do
      "Every #{n}h"
    else
      _ -> nil
    end
  end

  defp frequency(_, _), do: nil

  # Wall-clock time for numeric minute + hour. nil otherwise.
  defp clock_time(min, hour) do
    with m when not is_nil(m) <- ToolHelpers.parse_int(min),
         h when not is_nil(h) <- ToolHelpers.parse_int(hour) do
      {display_h, period} = to_12h(h)

      if m == 0,
        do: "#{display_h} #{period}",
        else: "#{display_h}:#{String.pad_leading("#{m}", 2, "0")} #{period}"
    else
      _ -> nil
    end
  end

  defp to_12h(0), do: {12, "AM"}
  defp to_12h(12), do: {12, "PM"}
  defp to_12h(h) when h < 12, do: {h, "AM"}
  defp to_12h(h), do: {h - 12, "PM"}

  # Day/month qualifier. nil when nothing meaningful to say.
  defp day_label(dow, dom, mon) do
    cond do
      dow != "*" and dom == "*" and mon == "*" -> format_dow(dow)
      dow == "*" and dom != "*" and mon == "*" -> "Day #{dom}"
      dow == "*" and dom != "*" and mon != "*" -> "#{month_name(mon)} #{dom}"
      dow == "*" and dom == "*" and mon == "*" -> "Daily"
      true -> nil
    end
  end

  defp format_dow("1-5"), do: "Weekdays"
  defp format_dow("0,6"), do: "Weekends"
  defp format_dow("6,0"), do: "Weekends"

  # Handles plain lists ("1,3,5"), plain ranges ("1-5"), and mixed lists of
  # ranges + singles ("1,3-5" -> "Mon, Wed-Fri") — each comma-separated token
  # is resolved independently instead of assuming the whole field is one kind.
  defp format_dow(dow) do
    dow
    |> String.split(",")
    |> Enum.map_join(", ", &format_dow_token/1)
  end

  defp format_dow_token(token) do
    if String.contains?(token, "-") do
      [start_day, end_day] = String.split(token, "-", parts: 2)
      "#{day_name(start_day)}-#{day_name(end_day)}"
    else
      day_name(token)
    end
  end

  defp day_name(n) when is_binary(n) do
    case ToolHelpers.parse_int(n) do
      nil -> "?"
      num -> Map.get(@days_of_week, num, "?")
    end
  end

  defp month_name(mon) do
    case ToolHelpers.parse_int(mon) do
      m when m in 1..12 -> Enum.at(@months, m - 1)
      _ -> mon
    end
  end

  defp combine(time, day) do
    case {time, day} do
      {nil, nil} -> :error
      {t, nil} -> {:ok, t}
      {nil, d} -> {:ok, d}
      {t, d} -> {:ok, "#{d} at #{t}"}
    end
  end
end
