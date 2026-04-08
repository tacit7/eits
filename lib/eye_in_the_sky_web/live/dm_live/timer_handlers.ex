defmodule EyeInTheSkyWeb.DmLive.TimerHandlers do
  @moduledoc """
  Handles schedule_timer and cancel_timer events from the DM page.
  """

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.OrchestratorTimers

  @presets_ms %{
    "5m" => 5 * 60 * 1_000,
    "10m" => 10 * 60 * 1_000,
    "15m" => 15 * 60 * 1_000,
    "30m" => 30 * 60 * 1_000,
    "1h" => 60 * 60 * 1_000
  }

  def handle_schedule_timer(%{"mode" => mode, "preset" => preset}, socket) do
    session_id = socket.assigns.session_id
    interval_ms = Map.get(@presets_ms, preset, 15 * 60 * 1_000)
    message = socket.assigns[:schedule_message] || OrchestratorTimers.default_message()

    case mode do
      "once" -> OrchestratorTimers.schedule_once(session_id, interval_ms, message)
      "repeating" -> OrchestratorTimers.schedule_repeating(session_id, interval_ms, message)
      _ -> OrchestratorTimers.schedule_once(session_id, interval_ms, message)
    end

    # Close the schedule modal; @active_timer updates via handle_info broadcast.
    {:noreply, assign(socket, :active_overlay, nil)}
  end

  def handle_cancel_timer(socket) do
    OrchestratorTimers.cancel(socket.assigns.session_id)
    {:noreply, socket}
  end
end
