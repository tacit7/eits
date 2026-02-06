defmodule EyeInTheSkyWebWeb.Helpers.ViewHelpers do
  @moduledoc """
  Shared view helpers for formatting dates, times, and rendering common UI elements.
  """

  use Phoenix.Component

  @doc """
  Parse datetime from various formats (DateTime struct, binary string, nil).
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
    # Go format: "2025-01-15 10:30:45.123456789 -0700 MST"
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
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 172_800 -> "yesterday"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
      diff_seconds < 2_592_000 -> "#{div(diff_seconds, 604_800)}w ago"
      true -> format_datetime_short(datetime)
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
        month_name = month_abbrev(month)
        "#{month_name} #{day}"

      _ ->
        datetime
    end
  end

  def format_datetime_short(_), do: "—"

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

  @doc """
  Render status badge component with proper styling.
  """
  def render_status_badge(assigns, agent) do
    status = derive_display_status(agent)
    badge_variant = status_to_badge(status)
    assigns = Map.merge(assigns, %{status: status, badge_variant: badge_variant})

    ~H"""
    <span class={"badge #{@badge_variant}"}>
      {@status}
    </span>
    """
  end

  @doc """
  Derive display status considering staleness.
  """
  def derive_display_status(agent, stale_threshold_hours \\ 24) do
    status = agent[:status] || agent.status

    if status in ["active", "working"] && is_stale?(agent, stale_threshold_hours) do
      "stale"
    else
      status
    end
  end

  @doc """
  Check if agent is stale based on updated_at timestamp.
  """
  def is_stale?(agent, stale_threshold_hours \\ 24) do
    case parse_updated_at(agent) do
      %DateTime{} = updated_at ->
        status = agent[:status] || agent.status
        diff_hours = DateTime.diff(DateTime.utc_now(), updated_at, :hour)
        diff_hours >= stale_threshold_hours && status in ["active", "working"]

      _ ->
        false
    end
  end

  # Map status to Daisy UI badge variants
  defp status_to_badge("active"), do: "badge-success"
  defp status_to_badge("working"), do: "badge-warning"
  defp status_to_badge("idle"), do: "badge-info"
  defp status_to_badge("stale"), do: "badge-warning badge-outline"
  defp status_to_badge("completed"), do: "badge-ghost"
  defp status_to_badge("failed"), do: "badge-error"
  defp status_to_badge(_), do: "badge-ghost"

  @doc """
  Render project badge component.
  """
  def render_project_badge(_assigns, nil), do: render_no_project()
  def render_project_badge(_assigns, ""), do: render_no_project()
  def render_project_badge(_assigns, "-"), do: render_no_project()

  def render_project_badge(_assigns, project_name) do
    assigns = %{project_name: project_name}

    ~H"""
    <span class="badge badge-primary">
      {@project_name}
    </span>
    """
  end

  defp render_no_project do
    assigns = %{}

    ~H"""
    <span class="badge badge-ghost">
      Unassigned
    </span>
    """
  end
end
