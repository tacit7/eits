defmodule EyeInTheSkyWeb.ChatLive.ChannelActions do
  @moduledoc """
  Handles channel membership events delegated from ChatLive.

  Keeps add/remove member and channel creation logic out of the main LiveView.
  """

  require Logger

  alias EyeInTheSky.{Channels, Sessions}
  alias EyeInTheSkyWeb.ControllerHelpers
  import Phoenix.LiveView, only: [put_flash: 3]

  @spec handle_add_agent(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_add_agent(socket, %{"session_id" => session_id_str}) do
    channel_id = socket.assigns.active_channel_id

    with session_id when not is_nil(session_id) <- ControllerHelpers.parse_int(session_id_str),
         {:ok, session} <- Sessions.get_session(session_id) do
      agent_id = session.agent_id

      case Channels.add_member(channel_id, agent_id, session_id) do
        {:ok, _member} ->
          broadcast_system_event(
            channel_id,
            "Agent @#{session_id} (#{session.name || "unnamed"}) joined the channel"
          )

          Logger.info("Added agent session=#{session_id} to channel=#{channel_id}")
          {:noreply, refresh_members_and_picker(socket)}

        {:error, changeset} ->
          Logger.warning("Failed to add member: #{inspect(changeset)}")
          {:noreply, put_flash(socket, :error, "Agent already in channel or invalid")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid session ID")}
    end
  end

  @spec handle_remove_agent(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_remove_agent(socket, %{"session_id" => session_id_str}) do
    channel_id = socket.assigns.active_channel_id

    with session_id when not is_nil(session_id) <- ControllerHelpers.parse_int(session_id_str),
         {:ok, session} <- Sessions.get_session(session_id) do
      Channels.remove_member(channel_id, session_id)

      broadcast_system_event(
        channel_id,
        "Agent @#{session_id} (#{session.name || "unnamed"}) left the channel"
      )

      Logger.info("Removed agent session=#{session_id} from channel=#{channel_id}")
      {:noreply, refresh_members_and_picker(socket)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid session ID")}
    end
  end

  @spec handle_create_channel(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_create_channel(socket, _params) do
    {:noreply, put_flash(socket, :info, "Channel creation coming soon")}
  end

  # Private

  defp refresh_members_and_picker(socket) do
    channel_id = socket.assigns.active_channel_id
    channel_members = EyeInTheSkyWeb.ChatLive.ChannelHelpers.load_channel_members(channel_id)
    search = socket.assigns[:session_search] || ""

    sessions_by_project =
      EyeInTheSkyWeb.ChatLive.ChannelHelpers.build_sessions_by_project(
        channel_members,
        socket.assigns.all_projects,
        search
      )

    socket
    |> Phoenix.Component.assign(:channel_members, channel_members)
    |> Phoenix.Component.assign(:sessions_by_project, sessions_by_project)
  end

  defp broadcast_system_event(channel_id, body) do
    {:ok, sys_msg} =
      EyeInTheSky.ChannelMessages.send_channel_message(%{
        channel_id: channel_id,
        session_id: nil,
        sender_role: "system",
        recipient_role: "agent",
        provider: "system",
        body: body
      })

    EyeInTheSky.Events.channel_message(channel_id, sys_msg)
  end
end
