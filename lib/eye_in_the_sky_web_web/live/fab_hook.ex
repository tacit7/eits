defmodule EyeInTheSkyWebWeb.FabHook do
  @moduledoc """
  LiveView on_mount hook that handles FAB favorite agents status requests
  and inline chat with bookmarked agents.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.{Agents, Channels, Messages, Sessions}
  alias EyeInTheSkyWeb.Claude.AgentManager

  require Logger

  @refresh_interval_ms 30_000

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "notifications")
    end

    socket =
      socket
      |> assign(:fab_mounted, true)
      |> assign(:fab_timer, nil)
      |> assign(:fab_subscribed_channels, MapSet.new())
      |> attach_hook(:fab_events, :handle_event, &handle_fab_event/3)
      |> attach_hook(:fab_info, :handle_info, &handle_fab_info/2)

    {:cont, socket}
  end

  defp handle_fab_event("fab_request_statuses", _params, socket) do
    statuses = fetch_bookmark_statuses()

    socket =
      socket
      |> push_event("fab_status_update", %{statuses: statuses})
      |> schedule_fab_refresh()

    {:halt, socket}
  end

  defp handle_fab_event("fab_open_chat", %{"session_id" => session_id}, socket) do
    socket =
      case resolve_and_subscribe(session_id, socket) do
        {:ok, channel, socket} ->
          messages =
            Messages.list_messages_for_channel(channel.id, limit: 20)
            |> Enum.map(&%{body: &1.body, sender_role: &1.sender_role})

          push_event(socket, "fab_chat_history", %{messages: messages})

        {:error, _reason, socket} ->
          socket
      end

    {:halt, socket}
  end

  defp handle_fab_event("fab_send_message", %{"session_id" => session_id, "body" => body}, socket) do
    case send_agent_message(session_id, body) do
      {:ok, channel_id} ->
        {:halt, maybe_subscribe_channel(socket, channel_id)}

      {:error, reason} ->
        {:halt, push_event(socket, "fab_chat_error", %{error: reason})}
    end
  end

  defp handle_fab_event(_event, _params, socket) do
    {:cont, socket}
  end

  defp handle_fab_info(:fab_refresh_statuses, socket) do
    statuses = fetch_bookmark_statuses()

    socket =
      socket
      |> push_event("fab_status_update", %{statuses: statuses})
      |> schedule_fab_refresh()

    {:halt, socket}
  end

  defp handle_fab_info({:new_message, %EyeInTheSkyWeb.Messages.Message{sender_role: role, body: body}}, socket)
       when role != "user" do
    {:halt, push_event(socket, "fab_chat_message", %{body: body, sender_role: role})}
  end

  defp handle_fab_info({event, _}, socket)
       when event in [:notification_created, :notifications_updated] do
    send_update(EyeInTheSkyWebWeb.Components.Sidebar, id: "app-sidebar", notification_count: :refresh)
    {:cont, socket}
  end

  defp handle_fab_info(_msg, socket) do
    {:cont, socket}
  end

  defp resolve_and_subscribe(session_id, socket) do
    with {:ok, session} <- resolve_session(session_id),
         {:ok, channel} <- find_global_channel(session.project_id) do
      {:ok, channel, maybe_subscribe_channel(socket, channel.id)}
    else
      {:error, reason} -> {:error, reason, socket}
    end
  end

  defp maybe_subscribe_channel(socket, channel_id) do
    subscribed = socket.assigns.fab_subscribed_channels

    if MapSet.member?(subscribed, channel_id) do
      socket
    else
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "channel:#{channel_id}:messages")
      assign(socket, :fab_subscribed_channels, MapSet.put(subscribed, channel_id))
    end
  end

  defp schedule_fab_refresh(socket) do
    if socket.assigns[:fab_timer], do: Process.cancel_timer(socket.assigns.fab_timer)
    timer = Process.send_after(self(), :fab_refresh_statuses, @refresh_interval_ms)
    assign(socket, :fab_timer, timer)
  end

  defp fetch_bookmark_statuses do
    Sessions.list_sessions_with_agent(include_archived: false)
    |> Enum.reduce(%{}, fn s, acc ->
      status = s.status || "idle"
      acc
      |> Map.put(to_string(s.id), status)
      |> then(fn a -> if s.uuid, do: Map.put(a, s.uuid, status), else: a end)
    end)
  end

  defp send_agent_message(session_id, body) do
    with {:ok, session} <- resolve_session(session_id),
         {:ok, channel} <- find_global_channel(session.project_id),
         {:ok, message} <- create_channel_message(channel, body),
         :ok <- broadcast_and_continue(session, channel, message, body) do
      {:ok, channel.id}
    else
      {:error, reason} ->
        Logger.error("FAB chat error: #{inspect(reason)}")
        {:error, to_string(reason)}
    end
  end

  defp resolve_session(session_id) do
    case Integer.parse(session_id) do
      {id, ""} -> Sessions.get_session(id)
      _ -> Sessions.get_session_by_uuid(session_id)
    end
  end

  defp find_global_channel(project_id) do
    channels =
      if project_id,
        do: Channels.list_channels_for_project(project_id),
        else: Channels.list_channels()

    channel =
      Enum.find(channels, fn c -> c.name in ["general", "#global"] end) ||
        List.first(channels)

    case channel do
      nil -> {:error, "No channel found"}
      ch -> {:ok, ch}
    end
  end

  defp create_channel_message(channel, body) do
    Messages.send_channel_message(%{
      channel_id: channel.id,
      session_id: "web-user",
      sender_role: "user",
      recipient_role: "agent",
      provider: "claude",
      body: body
    })
  end

  defp broadcast_and_continue(session, channel, message, body) do
    Phoenix.PubSub.broadcast(
      EyeInTheSkyWeb.PubSub,
      "channel:#{channel.id}:messages",
      {:new_message, message}
    )

    with {:ok, agent} <- Agents.get_agent(session.agent_id) do
      project_path = agent.git_worktree_path || File.cwd!()

      prompt = """
      REMINDER: Use i-chat-send MCP tool to send your response to the channel.

      User message: #{body}
      """

      AgentManager.continue_session(
        session.id,
        prompt,
        model: "sonnet",
        project_path: project_path
      )
    end

    :ok
  end
end
