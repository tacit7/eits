defmodule EyeInTheSkyWebWeb.FabHook do
  @moduledoc """
  LiveView on_mount hook that handles FAB favorite agents status requests
  and inline chat with bookmarked agents.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.{Messages, Sessions}
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
      |> assign(:fab_subscribed_sessions, MapSet.new())
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
      case resolve_session(session_id) do
        {:ok, session} ->
          socket = maybe_subscribe_session(socket, session.id)

          messages =
            Messages.list_recent_messages(session.id, 20)
            |> Enum.map(&%{body: &1.body, sender_role: &1.sender_role})

          push_event(socket, "fab_chat_history", %{messages: messages})

        {:error, reason} ->
          Logger.error("FAB open_chat error: #{inspect(reason)}")
          socket
      end

    {:halt, socket}
  end

  defp handle_fab_event("fab_send_message", %{"session_id" => session_id, "body" => body}, socket) do
    case send_session_message(session_id, body) do
      {:ok, session_id_int} ->
        {:halt, maybe_subscribe_session(socket, session_id_int)}

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
       when event in [:notification_created, :notifications_updated, :notification_read] do
    send_update(EyeInTheSkyWebWeb.Components.Sidebar, id: "app-sidebar", notification_count: :refresh)
    {:cont, socket}
  end

  defp handle_fab_info(_msg, socket) do
    {:cont, socket}
  end

  defp maybe_subscribe_session(socket, session_id) do
    subscribed = socket.assigns.fab_subscribed_sessions

    if MapSet.member?(subscribed, session_id) do
      socket
    else
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session_id}")
      assign(socket, :fab_subscribed_sessions, MapSet.put(subscribed, session_id))
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

  defp send_session_message(session_id, body) do
    with {:ok, session} <- resolve_session(session_id),
         {:ok, _message} <- Messages.send_message(%{
           session_id: session.id,
           sender_role: "user",
           recipient_role: "agent",
           provider: "claude",
           body: body
         }),
         :ok <- AgentManager.continue_session(session.id, body, model: "sonnet") do
      {:ok, session.id}
    else
      {:error, reason} ->
        Logger.error("FAB send_session_message error: #{inspect(reason)}")
        {:error, to_string(reason)}
    end
  end

  defp resolve_session(session_id) do
    case Integer.parse(session_id) do
      {id, ""} -> Sessions.get_session(id)
      _ -> Sessions.get_session_by_uuid(session_id)
    end
  end
end
