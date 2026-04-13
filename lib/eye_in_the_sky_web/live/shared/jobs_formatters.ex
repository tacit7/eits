defmodule EyeInTheSkyWeb.Live.Shared.JobsFormatters do
  @moduledoc false
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [month_name: 1]
  alias EyeInTheSky.Utils.ToolHelpers

  # ---------------------------------------------------------------------------
  # Schedule formatting
  # ---------------------------------------------------------------------------

  def format_schedule(%{schedule_type: "interval", schedule_value: val}) do
    case Integer.parse(val) do
      {s, _} when s >= 3600 -> "Every #{div(s, 3600)}h"
      {s, _} when s >= 60 -> "Every #{div(s, 60)}m"
      {s, _} -> "Every #{s}s"
      _ -> val
    end
  end

  def format_schedule(%{schedule_type: "cron", schedule_value: val}), do: describe_cron(val)
  def format_schedule(_), do: "?"

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

  def describe_cron(expr) do
    case String.split(String.trim(expr), ~r/\s+/) do
      [min, hour, dom, mon, dow] ->
        time = format_cron_time(min, hour)
        day = format_cron_day(dow, dom, mon)

        case {time, day} do
          {nil, nil} -> expr
          {t, nil} -> t
          {nil, d} -> d
          {t, d} -> "#{d} at #{t}"
        end

      _ ->
        expr
    end
  end

  def format_cron_time(min, hour) do
    case {parse_cron_num(min), parse_cron_num(hour)} do
      {{:ok, m}, {:ok, h}} ->
        period = if h >= 12, do: "PM", else: "AM"

        display_h =
          cond do
            h == 0 -> 12
            h > 12 -> h - 12
            true -> h
          end

        if m == 0,
          do: "#{display_h} #{period}",
          else: "#{display_h}:#{String.pad_leading("#{m}", 2, "0")} #{period}"

      {_, {:step, n}} ->
        "Every #{n}h"

      {{:step, n}, _} ->
        "Every #{n}m"

      _ ->
        nil
    end
  end

  def format_cron_day(dow, dom, mon) do
    cond do
      dow != "*" and dom == "*" and mon == "*" ->
        format_dow(dow)

      dow == "*" and dom != "*" and mon == "*" ->
        "Day #{dom}"

      dow == "*" and dom != "*" and mon != "*" ->
        "#{month_name(mon)} #{dom}"

      dow == "*" and dom == "*" and mon == "*" ->
        "Daily"

      true ->
        nil
    end
  end

  def format_dow(dow) do
    cond do
      dow == "1-5" ->
        "Weekdays"

      dow == "0,6" or dow == "6,0" ->
        "Weekends"

      String.contains?(dow, ",") ->
        dow |> String.split(",") |> Enum.map_join(", ", &day_name/1)

      String.contains?(dow, "-") ->
        [from, to] = String.split(dow, "-", parts: 2)
        "#{day_name(from)}-#{day_name(to)}"

      true ->
        day_name(dow)
    end
  end

  def day_name(n) when is_integer(n), do: Map.get(@days_of_week, n, "?")

  def day_name(n) when is_binary(n) do
    case Integer.parse(n) do
      {num, _} -> Map.get(@days_of_week, num, "?")
      _ -> "?"
    end
  end

  def day_name(_), do: "?"

  def parse_cron_num("*"), do: {:ok, :any}

  def parse_cron_num("*/" <> step) do
    if n = ToolHelpers.parse_int(step), do: {:step, n}, else: :error
  end

  def parse_cron_num(s) do
    if n = ToolHelpers.parse_int(s), do: {:ok, n}, else: :error
  end

  # ---------------------------------------------------------------------------
  # Timezone
  # ---------------------------------------------------------------------------

  def system_timezone do
    System.get_env("TZ") || detect_macos_timezone() || "UTC"
  end

  defp detect_macos_timezone do
    case System.cmd("readlink", ["/etc/localtime"], stderr_to_stdout: true) do
      {path, 0} ->
        case Regex.run(~r"zoneinfo/(.+)$", String.trim(path)) do
          [_, tz] -> tz
          _ -> nil
        end

      _ ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Badge and display helpers
  # ---------------------------------------------------------------------------

  def type_badge_class("spawn_agent"), do: "badge-primary"
def type_badge_class("mix_task"), do: "badge-accent"
  def type_badge_class(_), do: "badge-ghost"

  def type_label("spawn_agent"), do: "Agent"
def type_label("mix_task"), do: "Mix"
  def type_label(t), do: t

  def status_badge_class("running"), do: "badge-info"
  def status_badge_class("completed"), do: "badge-success"
  def status_badge_class("failed"), do: "badge-error"
  def status_badge_class(_), do: "badge-ghost"

  # Returns :disabled | :running | :failed | :healthy for a job row.
  def job_row_state(job, running_ids, last_run_map) do
    cond do
      job.enabled != 1 -> :disabled
      MapSet.member?(running_ids, job.id) -> :running
      Map.get(last_run_map, job.id) == "failed" -> :failed
      true -> :healthy
    end
  end

  def row_border_class(:disabled), do: "border-l-4 border-base-content/20"
  def row_border_class(:running), do: "border-l-4 border-warning"
  def row_border_class(:failed), do: "border-l-4 border-error"
  def row_border_class(:healthy), do: "border-l-4 border-success"

  def cfg(config, key) do
    case config do
      %{^key => val} when is_binary(val) -> val
      %{^key => val} when is_list(val) -> Enum.join(val, ", ")
      %{^key => val} -> to_string(val)
      _ -> ""
    end
  end
end
