defmodule EyeInTheSkyWeb.ChatLive.EventHandlers do
  @moduledoc false

  use EyeInTheSkyWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [cancel_upload: 3, put_flash: 3, push_patch: 2]

  alias EyeInTheSky.{ChannelMessages, Channels, FileAttachments, MessageReactions, Messages, Repo}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Claude.ChannelProtocol
  alias EyeInTheSkyWeb.ChatLive.ChannelActions
  alias EyeInTheSkyWeb.ChatLive.ChannelDataLoader
  alias EyeInTheSkyWeb.ChatLive.ChannelHelpers
  alias EyeInTheSkyWeb.ChatPresenter
  import EyeInTheSkyWeb.Helpers.UploadHelpers
  import EyeInTheSkyWeb.Helpers.ChannelRoutingHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]

  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, EyeInTheSkyWeb.Live.Shared.NotificationHelpers.set_notify_on_stop(socket, params)}

  def handle_event("change_channel", %{"channel_id" => channel_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?channel_id=#{channel_id}")}
  end

  def handle_event("send_channel_message", %{"channel_id" => channel_id, "body" => body}, socket) do
    session_id = get_session_id(socket)
    {image_infos, content_blocks} = consume_and_persist_agent_images(socket)

    case ChannelMessages.send_channel_message(%{
           channel_id: channel_id,
           session_id: session_id,
           sender_role: "user",
           recipient_role: "agent",
           provider: "claude",
           body: body
         }) do
      {:ok, message} ->
        Enum.each(image_infos, fn {path, entry, size} ->
          FileAttachments.create_attachment(%{
            message_id: message.id,
            filename: Path.basename(path),
            original_filename: entry.client_name,
            content_type: entry.client_type || mime_from_ext(entry.client_name),
            size_bytes: size,
            storage_path: path
          })
        end)

        serialized =
          message
          |> Repo.preload([:session, :reactions, :attachments])
          |> ChatPresenter.serialize_message()

        Channels.mark_as_read(channel_id, session_id)
        ChannelHelpers.route_to_members(channel_id, body, session_id, content_blocks)

        {:noreply,
         socket
         |> assign(:messages, socket.assigns.messages ++ [serialized])
         |> refresh_members_and_picker()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  def handle_event(
        "send_direct_message",
        %{"session_id" => target_session_id_str, "body" => body} = params,
        socket
      ) do
    session_id = get_session_id(socket)
    channel_id = params["channel_id"] || socket.assigns.active_channel_id
    target_session_id = parse_int(target_session_id_str)

    case create_dm_channel_message(channel_id, body, session_id) do
      {:ok, _message} ->
        if target_session_id do
          case Channels.get_channel(channel_id) do
            nil ->
              :ok

            channel ->
              channel_ctx = %{id: channel.id, name: channel.name}
              prompt = ChannelProtocol.build_prompt(:direct, body, channel_ctx)
              AgentManager.send_message(target_session_id, prompt, channel_id: channel_id)
          end
        end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  def handle_event("add_agent_to_channel", params, socket),
    do: ChannelActions.handle_add_agent(socket, params)

  def handle_event("remove_agent_from_channel", params, socket),
    do: ChannelActions.handle_remove_agent(socket, params)

  def handle_event("open_thread", %{"message_id" => message_id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/chat?channel_id=#{socket.assigns.active_channel_id}&thread_id=#{message_id}"
     )}
  end

  def handle_event("close_thread", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?channel_id=#{socket.assigns.active_channel_id}")}
  end

  def handle_event(
        "send_thread_reply",
        %{"parent_message_id" => parent_id, "body" => body},
        socket
      ) do
    session_id = get_session_id(socket)
    channel_id = socket.assigns.active_channel_id

    case ChannelMessages.create_thread_reply(parent_id, %{
           channel_id: channel_id,
           session_id: session_id,
           sender_role: "user",
           recipient_role: "agent",
           provider: "claude",
           body: body
         }) do
      {:ok, _message} ->
        active_thread = ChannelDataLoader.load_thread(parent_id)
        {:noreply, assign(socket, :active_thread, active_thread)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to send reply")}
    end
  end

  def handle_event("toggle_reaction", %{"message_id" => message_id, "emoji" => emoji}, socket) do
    session_id = get_session_id(socket)

    case MessageReactions.toggle_reaction(message_id, session_id, emoji) do
      {:ok, _action} ->
        {:noreply, assign(socket, :messages, reload_messages(socket))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to add reaction")}
    end
  end

  def handle_event("delete_message", %{"id" => id_str}, socket) do
    case parse_int(id_str) do
      nil ->
        {:noreply, socket}

      id ->
        message = Messages.get_message!(id)
        {:ok, _} = Messages.delete_message(message)
        {:noreply, assign(socket, :messages, reload_messages(socket))}
    end
  end

  def handle_event("search_sessions", %{"session_search" => query}, socket) do
    sessions_by_project =
      ChannelHelpers.build_sessions_by_project(
        socket.assigns.channel_members,
        socket.assigns.all_projects,
        query
      )

    {:noreply,
     socket
     |> assign(:session_search, query)
     |> assign(:sessions_by_project, sessions_by_project)}
  end

  def handle_event("toggle_members", _params, socket) do
    {:noreply, assign(socket, :show_members, !socket.assigns.show_members)}
  end

  def handle_event("toggle_agent_drawer", _params, socket) do
    {:noreply, assign(socket, :show_agent_drawer, !socket.assigns.show_agent_drawer)}
  end

  def handle_event("set_sender_filter", %{"session_id" => ""}, socket) do
    {:noreply, assign(socket, :sender_filter, nil)}
  end

  def handle_event("set_sender_filter", %{"session_id" => session_id}, socket) do
    {:noreply, assign(socket, :sender_filter, session_id)}
  end

  def handle_event("validate_agent_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_agent_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :agent_images, ref)}
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("load_older_messages", %{"before_id" => before_id_str}, socket) do
    channel_id = socket.assigns.active_channel_id

    case parse_int(before_id_str) do
      nil ->
        {:noreply, socket}

      before_id ->
        older =
          ChannelMessages.list_messages_for_channel(channel_id, before_id: before_id, limit: 50)
          |> ChatPresenter.serialize_messages()

        messages = older ++ socket.assigns.messages
        has_more = length(older) == 50

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:has_more_messages, has_more)}
    end
  end

  def handle_event("create_channel", params, socket),
    do: ChannelActions.handle_create_channel(socket, params)

  def handle_event("create_agent", params, socket),
    do: ChannelActions.handle_create_agent(socket, params)

  def handle_event("show_new_channel", _params, socket) do
    {:noreply, assign(socket, :new_channel_name, "")}
  end

  def handle_event("cancel_new_channel", _params, socket) do
    {:noreply, assign(socket, :new_channel_name, nil)}
  end

  def handle_event("update_channel_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_channel_name, value)}
  end

  # Private helpers

  defp get_session_id(socket), do: socket.assigns[:session_id]

  defp reload_messages(socket) do
    ChannelMessages.list_messages_for_channel(socket.assigns.active_channel_id)
    |> ChatPresenter.serialize_messages()
  end

  defp refresh_members_and_picker(socket) do
    channel_id = socket.assigns.active_channel_id
    channel_members = ChannelHelpers.load_channel_members(channel_id)
    search = socket.assigns[:session_search] || ""

    sessions_by_project =
      ChannelHelpers.build_sessions_by_project(
        channel_members,
        socket.assigns.all_projects,
        search
      )

    socket
    |> assign(:channel_members, channel_members)
    |> assign(:sessions_by_project, sessions_by_project)
  end

end
