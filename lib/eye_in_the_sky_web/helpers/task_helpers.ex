defmodule EyeInTheSkyWeb.Helpers.TaskHelpers do
  @moduledoc """
  Task-specific display helpers: due dates, aging indicators, overdue checks.
  """

  alias EyeInTheSkyWeb.Helpers.DateHelpers

  @doc """
  Format a due date for display: "Today", "Tomorrow", "Overdue", or "Jan 15".
  """
  def format_due_date(nil), do: ""

  def format_due_date(datetime) when is_binary(datetime) do
    case Date.from_iso8601(String.slice(datetime, 0..9)) do
      {:ok, date} ->
        today = Date.utc_today()

        cond do
          Date.compare(date, today) == :eq -> "Today"
          Date.compare(date, Date.add(today, 1)) == :eq -> "Tomorrow"
          Date.compare(date, today) == :lt -> "Overdue"
          true -> Calendar.strftime(date, "%b %d")
        end

      _ ->
        datetime
    end
  end

  def format_due_date(_), do: ""

  @doc """
  CSS class for due date based on urgency.
  """
  def due_date_class(nil), do: "text-base-content/30"

  def due_date_class(datetime) when is_binary(datetime) do
    case Date.from_iso8601(String.slice(datetime, 0..9)) do
      {:ok, date} ->
        today = Date.utc_today()

        cond do
          Date.compare(date, today) == :lt -> "text-error font-medium"
          Date.compare(date, today) == :eq -> "text-warning font-medium"
          true -> "text-base-content/30"
        end

      _ ->
        "text-base-content/30"
    end
  end

  def due_date_class(_), do: "text-base-content/30"

  @doc """
  Check if a due date is overdue.
  """
  def is_overdue?(nil), do: false

  def is_overdue?(datetime) when is_binary(datetime) do
    case Date.from_iso8601(String.slice(datetime, 0..9)) do
      {:ok, date} -> Date.compare(date, Date.utc_today()) == :lt
      _ -> false
    end
  end

  def is_overdue?(_), do: false

  @doc """
  Check if a due date is today.
  """
  def is_due_today?(nil), do: false

  def is_due_today?(datetime) when is_binary(datetime) do
    case Date.from_iso8601(String.slice(datetime, 0..9)) do
      {:ok, date} -> Date.compare(date, Date.utc_today()) == :eq
      _ -> false
    end
  end

  def is_due_today?(_), do: false

  @doc """
  Format a date for HTML date input (YYYY-MM-DD).
  """
  def format_date_input(nil), do: ""
  def format_date_input(datetime) when is_binary(datetime), do: String.slice(datetime, 0..9)
  def format_date_input(_), do: ""

  @doc """
  Return the number of days since a task was last updated.
  Accepts ISO8601 string or DateTime. Returns nil if unparseable.
  """
  def days_since_update(nil), do: nil

  def days_since_update(%DateTime{} = dt) do
    DateTime.diff(DateTime.utc_now(), dt, :second) |> div(86400)
  end

  def days_since_update(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} ->
        days_since_update(dt)

      _ ->
        case DateHelpers.parse_datetime(str) do
          {:ok, dt} -> days_since_update(dt)
          :error -> nil
        end
    end
  end

  def days_since_update(_), do: nil

  @doc """
  CSS classes for card aging indicator.
  Returns {border_class, label} or nil if card is fresh.
  """
  def card_aging_indicator(updated_at) do
    case days_since_update(updated_at) do
      nil -> nil
      days when days >= 14 -> {"border-l-2 border-l-error/60", "#{days}d stale"}
      days when days >= 7 -> {"border-l-2 border-l-warning/60", "#{days}d idle"}
      _days -> nil
    end
  end
end
