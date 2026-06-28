defmodule EyeInTheSkyWeb.ChatLive.PubSubHandlers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.ChannelMessages
  alias EyeInTheSkyWeb.ChatLive.ChannelHelpers
  alias EyeInTheSkyWeb.ChatPresenter
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers

  require Logger

  def handle_info({:agent_working, msg}, socket) do
    AgentStatusHelpers.handle_agent_working(socket, msg, fn socket, session_id ->
      assign(socket, :working_agents, Map.put(socket.assigns.working_agents, session_id, true))
    end)
  end

  def handle_info({:agent_stopped, msg}, socket) do
    AgentStatusHelpers.handle_agent_stopped(socket, msg, fn socket, session_id ->
      assign(socket, :working_agents, Map.delete(socket.assigns.working_agents, session_id))
    end)
  end

  def handle_info({:agent_created, _}, socket), do: {:noreply, socket}
  def handle_info({:agent_updated, _}, socket), do: {:noreply, socket}
  def handle_info({:agent_deleted, _}, socket), do: {:noreply, socket}

  def handle_info({:new_message, message}, socket) do
    Logger.info(
      "📨 Received new_message broadcast for channel #{socket.assigns.active_channel_id}"
    )

    # Guard against duplicate broadcasts (broadcast_and_return fires immediately;
    # NotifyListener fires again via Postgres LISTEN/NOTIFY for the same insert).
    already_present = MapSet.member?(socket.assigns.received_message_ids, message.id)

    if already_present do
      Logger.info("📬 Skipping duplicate message id=#{message.id}")
      {:noreply, socket}
    else
      # Preload associations required by ChatPresenter.serialize_message,
      # then push a delta — avoids re-serializing the entire message history.
      serialized =
        message
        |> ChannelMessages.preload_for_serialization()
        |> ChatPresenter.serialize_message()

      channels = load_channels(socket.assigns.project_id)
      unread_counts = ChannelHelpers.calculate_unread_counts(channels, get_session_id(socket))

      Logger.info("📬 Pushed delta for message id=#{message.id}")

      Phoenix.LiveView.send_update(EyeInTheSkyWeb.Components.Rail,
        id: "app-rail",
        unread_counts: unread_counts
      )

      {:noreply,
       socket
       |> assign(:received_message_ids, MapSet.put(socket.assigns.received_message_ids, message.id))
       |> assign(:unread_counts, unread_counts)
       |> Phoenix.LiveView.push_event("chat:message_appended", %{message: serialized})}
    end
  end

  # Private helpers

  defp get_session_id(socket), do: socket.assigns[:session_id]

  defp load_channels(project_id) do
    alias EyeInTheSky.Channels

    case Channels.list_channels_for_project(project_id) do
      channels when is_list(channels) -> channels
      _ -> []
    end
  end
end
