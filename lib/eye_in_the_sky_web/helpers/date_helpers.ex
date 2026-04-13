defmodule EyeInTheSkyWeb.Helpers.DateHelpers do
  @moduledoc """
  Datetime and time formatting helpers.
  """

  @doc """
  Coerce a raw datetime value (nil | DateTime | NaiveDateTime | binary) to a DateTime.
  Returns a fallback epoch datetime when the value is nil or unparseable.
  """
  def coerce_datetime(nil), do: ~U[1970-01-01 00:00:00Z]
  def coerce_datetime(%DateTime{} = dt), do: dt
  def coerce_datetime(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  def coerce_datetime(str) when is_binary(str) do
    case parse_datetime(str) do
      {:ok, dt} -> dt
      :error -> ~U[1970-01-01 00:00:00Z]
    end
  end

  def coerce_datetime(_), do: ~U[1970-01-01 00:00:00Z]

  @doc """
  Parse datetime from a struct's updated_at field.
  Returns a DateTime struct or a fallback epoch datetime.
  """
  def parse_updated_at(%{updated_at: nil}), do: ~U[1970-01-01 00:00:00Z]
  def parse_updated_at(%{updated_at: %DateTime{} = dt}), do: dt

  def parse_updated_at(%{updated_at: str}) when is_binary(str) do
    case parse_datetime(str) do
      {:ok, dt} -> dt
      :error -> ~U[1970-01-01 00:00:00Z]
    end
  end

  @doc """
  Parse Go datetime strings to Elixir DateTime.
  Go format: "2025-01-15 10:30:45.123456789 -0700 MST"
  """
  def parse_datetime(datetime) when is_binary(datetime) do
    case String.split(datetime, " ", parts: 3) do
      [date, time | _] ->
        time_clean = String.slice(time, 0..7)

        case DateTime.from_iso8601("#{date}T#{time_clean}Z") do
          {:ok, dt, _} -> {:ok, dt}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  def parse_datetime(_), do: :error

  @doc """
  Format relative time (e.g., "5m ago", "2h ago", "yesterday").
  """
  def relative_time(nil), do: "—"

  def relative_time(datetime) when is_binary(datetime) do
    case parse_datetime(datetime) do
      {:ok, dt} -> relative_time(dt)
      :error -> format_datetime_short(datetime)
    end
  end

  def relative_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 172_800 -> "yesterday"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86_400)}d ago"
      diff_seconds < 2_592_000 -> "#{div(diff_seconds, 604_800)}w ago"
      true -> format_datetime_short(datetime)
    end
  end

  def relative_time(%NaiveDateTime{} = naive) do
    case DateTime.from_naive(naive, "Etc/UTC") do
      {:ok, dt} -> relative_time(dt)
      :error -> "—"
    end
  end

  def relative_time(_), do: "—"

  @doc """
  Format full datetime for tooltips.
  """
  def format_datetime_full(nil), do: ""

  def format_datetime_full(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end

  def format_datetime_full(datetime) when is_binary(datetime) do
    case String.split(datetime, " ", parts: 3) do
      [date, time | _] -> "#{date} #{String.slice(time, 0..7)}"
      _ -> datetime
    end
  end

  def format_datetime_full(_), do: ""

  @doc """
  Format short datetime (e.g., "Jan 15").
  """
  def format_datetime_short(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d")
  end

  def format_datetime_short(datetime) when is_binary(datetime) do
    case String.split(datetime, "-") do
      [_year, month, rest] ->
        day = String.slice(rest, 0..1)
        "#{month_abbrev(month)} #{day}"

      _ ->
        datetime
    end
  end

  def format_datetime_short(_), do: "—"

  @doc """
  Format a datetime value as "HH:MM" (wall-clock time only).
  """
  def format_time(nil), do: ""
  def format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  def format_time(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")

  def format_time(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%H:%M")
      _ -> ""
    end
  end

  def format_time(_), do: ""

  @doc """
  Format a datetime value as "Mon DD, HH:MM" (e.g. "Jan 15, 09:30").
  """
  def format_datetime_short_time(nil), do: ""
  def format_datetime_short_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %H:%M")
  def format_datetime_short_time(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %H:%M")

  def format_datetime_short_time(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%b %d, %H:%M")
      _ -> ""
    end
  end

  def format_datetime_short_time(_), do: ""

  @doc """
  Format relative time including future times (e.g. "in 5m", "3h ago").
  Used for cron job scheduling display.
  """
  def format_relative_time(nil), do: "-"

  def format_relative_time(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(dt, now, :second)
    format_relative_diff(diff)
  end

  def format_relative_time(%NaiveDateTime{} = ndt) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(ndt, now, :second)
    format_relative_diff(diff)
  end

  def format_relative_time(iso) when is_binary(iso) do
    with cleaned <- String.replace(iso, "Z", ""),
         {:ok, ndt} <- NaiveDateTime.from_iso8601(cleaned) do
      now = NaiveDateTime.utc_now()
      diff = NaiveDateTime.diff(ndt, now, :second)
      format_relative_diff(diff)
    else
      {:error, _} -> "-"
    end
  end

  def format_relative_time(_), do: "-"

  @doc """
  Extract the date portion from a timestamp string (e.g. "2026-01-15 10:30:00" → "2026-01-15").
  """
  def format_date(nil), do: "—"

  def format_date(ts) when is_binary(ts) do
    case String.split(ts, " ") do
      [date | _] -> date
      _ -> ts
    end
  end

  def format_date(_), do: "—"

  @doc """
  Month abbreviation from cron month field ("1"-"12").
  """
  def month_name("1"), do: "Jan"
  def month_name("2"), do: "Feb"
  def month_name("3"), do: "Mar"
  def month_name("4"), do: "Apr"
  def month_name("5"), do: "May"
  def month_name("6"), do: "Jun"
  def month_name("7"), do: "Jul"
  def month_name("8"), do: "Aug"
  def month_name("9"), do: "Sep"
  def month_name("10"), do: "Oct"
  def month_name("11"), do: "Nov"
  def month_name("12"), do: "Dec"
  def month_name(m), do: m

  defp format_relative_diff(secs) when secs > 0 do
    cond do
      secs < 60 -> "in #{secs}s"
      secs < 3600 -> "in #{div(secs, 60)}m"
      secs < 86_400 -> "in #{div(secs, 3600)}h"
      true -> "in #{div(secs, 86_400)}d"
    end
  end

  defp format_relative_diff(secs) do
    abs_secs = abs(secs)

    cond do
      abs_secs < 60 -> "#{abs_secs}s ago"
      abs_secs < 3600 -> "#{div(abs_secs, 60)}m ago"
      abs_secs < 86_400 -> "#{div(abs_secs, 3600)}h ago"
      true -> "#{div(abs_secs, 86_400)}d ago"
    end
  end

  defp month_abbrev("01"), do: "Jan"
  defp month_abbrev("02"), do: "Feb"
  defp month_abbrev("03"), do: "Mar"
  defp month_abbrev("04"), do: "Apr"
  defp month_abbrev("05"), do: "May"
  defp month_abbrev("06"), do: "Jun"
  defp month_abbrev("07"), do: "Jul"
  defp month_abbrev("08"), do: "Aug"
  defp month_abbrev("09"), do: "Sep"
  defp month_abbrev("10"), do: "Oct"
  defp month_abbrev("11"), do: "Nov"
  defp month_abbrev("12"), do: "Dec"
  defp month_abbrev(_), do: "?"
end
