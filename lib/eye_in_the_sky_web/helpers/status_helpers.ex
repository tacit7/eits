defmodule EyeInTheSkyWeb.Helpers.StatusHelpers do
  @moduledoc """
  Agent and session status display helpers: badges, idle tiers, staleness.
  """

  use Phoenix.Component

  alias EyeInTheSkyWeb.Helpers.DateHelpers

  @doc """
  Render status badge component with proper styling.
  """
  def render_status_badge(assigns, agent) do
    display_status = derive_display_status(agent)
    badge_variant = status_to_badge(display_status)
    label = status_label(display_status)

    assigns =
      Map.merge(assigns, %{status: display_status, badge_variant: badge_variant, label: label})

    ~H"""
    <span class={"badge #{@badge_variant}"}>
      {@label}
    </span>
    """
  end

  @doc """
  Derive display status with idle staleness tiers and failure reason tiers.

  Returns one of: working | compacting | idle | idle_stale | idle_dead |
  completed | failed | failed_billing | failed_auth | failed_rate_limit |
  failed_timeout | failed_retry_exhausted

  Sessions carry `status_reason` (see `EyeInTheSky.Sessions.Session`); Agents do
  not. `Map.get/3` gracefully handles both.
  """
  def derive_display_status(agent, _stale_threshold_hours \\ 24) do
    case agent.status do
      "idle" -> idle_tier(agent)
      "failed" -> failed_tier(Map.get(agent, :status_reason))
      other -> other
    end
  end

  @doc """
  Map `status_reason` to a display status so the badge can distinguish
  billing / auth / rate-limit / timeout failures from a generic crash.
  """
  def failed_tier("billing_error"), do: "failed_billing"
  def failed_tier("authentication_error"), do: "failed_auth"
  def failed_tier("rate_limit_error"), do: "failed_rate_limit"
  def failed_tier("watchdog_timeout"), do: "failed_timeout"
  def failed_tier("retry_exhausted"), do: "failed_retry_exhausted"
  def failed_tier(_), do: "failed"

  @doc """
  Compute idle staleness tier based on last_activity_at.
  Returns "idle" | "idle_stale" | "idle_dead"
  """
  def idle_tier(agent) do
    hours_since = agent.last_activity_at |> hours_since_activity()

    cond do
      is_nil(hours_since) -> "idle"
      hours_since >= 24 -> "idle_dead"
      hours_since >= 1 -> "idle_stale"
      true -> "idle"
    end
  end

  defp hours_since_activity(nil), do: nil

  defp hours_since_activity(%DateTime{} = dt),
    do: DateTime.diff(DateTime.utc_now(), dt, :hour)

  defp hours_since_activity(str) when is_binary(str) do
    dt = parse_datetime_string(str)
    if dt, do: DateTime.diff(DateTime.utc_now(), dt, :hour), else: nil
  end

  defp hours_since_activity(_), do: nil

  defp parse_datetime_string(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} ->
        dt

      _ ->
        case DateHelpers.parse_datetime(str) do
          {:ok, dt} -> dt
          :error -> nil
        end
    end
  end

  @doc """
  Check if agent is stale (idle >= 1h).
  """
  def stale?(agent, _stale_threshold_hours \\ 1) do
    idle_tier(agent) in ["idle_stale", "idle_dead"]
  end

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

  defp status_label("working"), do: "Working"
  defp status_label("compacting"), do: "Compacting"
  defp status_label("idle"), do: "Idle"
  defp status_label("idle_stale"), do: "Idle"
  defp status_label("idle_dead"), do: "Idle"
  defp status_label("completed"), do: "Done"
  defp status_label("failed"), do: "Failed"
  defp status_label("failed_billing"), do: "Billing"
  defp status_label("failed_auth"), do: "Auth"
  defp status_label("failed_rate_limit"), do: "Rate limited"
  defp status_label("failed_timeout"), do: "Timed out"
  defp status_label("failed_retry_exhausted"), do: "Failed"
  defp status_label(s), do: s

  def status_to_badge("working"), do: "badge-success"
  def status_to_badge("compacting"), do: "badge-warning"
  def status_to_badge("idle"), do: "badge-ghost"
  def status_to_badge("idle_stale"), do: "badge-warning badge-outline"
  def status_to_badge("idle_dead"), do: "badge-error badge-outline"
  def status_to_badge("completed"), do: "badge-ghost"
  def status_to_badge("failed"), do: "badge-error"
  # All systemic-failure tiers render red. Rate-limit uses an outline to hint
  # it is recoverable by waiting rather than a dead crash.
  def status_to_badge("failed_billing"), do: "badge-error"
  def status_to_badge("failed_auth"), do: "badge-error"
  def status_to_badge("failed_rate_limit"), do: "badge-error badge-outline"
  def status_to_badge("failed_timeout"), do: "badge-error"
  def status_to_badge("failed_retry_exhausted"), do: "badge-error"
  def status_to_badge(_), do: "badge-ghost"

  defp render_no_project do
    assigns = %{}

    ~H"""
    <span class="badge badge-ghost">
      Unassigned
    </span>
    """
  end
end
