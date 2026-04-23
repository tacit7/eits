defmodule EyeInTheSkyWeb.Live.Shared.NotificationHelpers do
  @moduledoc """
  Shared handlers for push-notification JS hook events.

  The `PushNotifications` hook in `assets/js/push_notifications.js` fires
  `set_notify_on_stop` on whichever LiveView mounts it. Every LiveView that
  uses the hook must expose a matching `handle_event/3` clause, so this
  module centralizes the logic.
  """

  import Phoenix.Component, only: [assign: 3]

  @truthy [true, "true", "on", 1, "1"]

  @doc """
  Assigns `:notify_on_stop` on the socket from a truthy `enabled` param.

  ## Usage in a LiveView

      def handle_event("set_notify_on_stop", params, socket),
        do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}
  """
  def set_notify_on_stop(socket, %{"enabled" => enabled}) do
    assign(socket, :notify_on_stop, enabled in @truthy)
  end

  def set_notify_on_stop(socket, _params), do: socket
end
