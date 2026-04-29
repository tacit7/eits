defmodule EyeInTheSkyWeb.ChatLive.PubSubHandlers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.ChatLive.ChannelHelpers
  alias EyeInTheSkyWeb.ChatPresenter
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers
  alias EyeInTheSky.ChannelMessages

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

  def handle_info({:agent_updated, _}, socket), do: {:noreply, socket}

  def handle_info({:new_message, _message}, socket) do
    Logger.info(
      "📨 Received new_message broadcast for channel #{socket.assigns.active_channel_id}"
    )

    messages = reload_messages(socket)

    Logger.info("📬 Loaded #{length(messages)} messages from DB")

    channels = load_channels(socket.assigns.project_id)
    unread_counts = ChannelHelpers.calculate_unread_counts(channels, get_session_id(socket))

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:unread_counts, unread_counts)}
  end

  # Private helpers

  defp get_session_id(socket), do: socket.assigns[:session_id]

  defp reload_messages(socket) do
    ChannelMessages.list_messages_for_channel(socket.assigns.active_channel_id)
    |> ChatPresenter.serialize_messages()
  end

  defp load_channels(project_id) do
    alias EyeInTheSky.Channels

    case Channels.list_channels_for_project(project_id) do
      channels when is_list(channels) -> channels
      _ -> []
    end
  end
end
