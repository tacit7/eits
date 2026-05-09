defmodule EyeInTheSkyWeb.FloatingChatLive do
  @moduledoc """
  LiveView on_mount hook that handles FAB favorite agents status requests
  and inline chat with bookmarked agents.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]
  import Ecto.Query

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.{Messages, Repo, Sessions}

  require Logger

  # Polling interval for bookmark status refresh.
  # Timer is owned by the consuming LiveView process; cleanup happens at view termination.
  @refresh_interval_ms 30_000

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_notifications()
      EyeInTheSky.Events.subscribe_projects()
      EyeInTheSky.Events.subscribe_channels()
    end

    socket =
      socket
      |> assign(:fab_mounted, true)
      |> assign(:fab_timer, nil)
      |> assign(:fab_active_session_id, nil)
      |> assign(:config_guide_active_session_id, nil)
      |> assign(:fab_bookmarks, [])
      |> assign(:fab_statuses, %{})
      |> attach_hook(:fab_events, :handle_event, &handle_fab_event/3)
      |> attach_hook(:fab_info, :handle_info, &handle_fab_info/2)

    {:cont, socket}
  end

  defp handle_fab_event("fab_set_bookmarks", %{"bookmarks" => bookmarks}, socket) do
    bookmarks = if is_list(bookmarks), do: bookmarks, else: []
    statuses = fetch_bookmark_statuses(bookmarks)

    socket =
      socket
      |> assign(:fab_bookmarks, bookmarks)
      |> assign(:fab_statuses, statuses)
      |> schedule_fab_refresh()

    update_fab_component(socket)
    {:halt, socket}
  end

  defp handle_fab_event("fab_request_statuses", _params, socket) do
    statuses = fetch_bookmark_statuses(socket.assigns.fab_bookmarks)

    socket =
      socket
      |> assign(:fab_statuses, statuses)
      |> schedule_fab_refresh()

    update_fab_component(socket)
    {:halt, socket}
  end

  defp handle_fab_event("fab_open_chat", %{"session_id" => session_id}, socket) do
    socket =
      case Sessions.resolve(session_id) do
        {:ok, session} ->
          socket = switch_active_session(socket, session.id)

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

  defp handle_fab_event("fab_close_chat", _params, socket) do
    {:halt, unsubscribe_active_session(socket)}
  end

  defp handle_fab_event("fab_send_message", %{"session_id" => session_id, "body" => body}, socket) do
    case send_session_message(session_id, body) do
      {:ok, session_id_int} ->
        {:halt, switch_active_session(socket, session_id_int)}

      {:error, reason} ->
        {:halt, push_event(socket, "fab_chat_error", %{error: reason})}
    end
  end

  defp handle_fab_event("config_guide_open_chat", %{"session_id" => session_id}, socket) do
    socket =
      case Sessions.resolve(session_id) do
        {:ok, session} ->
          socket = unsubscribe_config_guide_session(socket)
          EyeInTheSky.Events.subscribe_session(session.id)
          socket = assign(socket, :config_guide_active_session_id, session.id)

          messages =
            Messages.list_recent_messages(session.id, 20)
            |> Enum.map(
              &%{
                id: &1.id,
                session_id: &1.session_id,
                body: &1.body,
                sender_role: &1.sender_role,
                inserted_at: to_string(&1.inserted_at)
              }
            )

          push_event(socket, "config_guide_history", %{messages: messages})

        {:error, reason} ->
          Logger.error("ConfigGuide open_chat error: #{inspect(reason)}")
          push_event(socket, "config_guide_error", %{error: "Failed to open session"})
      end

    {:halt, socket}
  end

  defp handle_fab_event(
         "config_guide_send_message",
         %{"session_id" => session_id, "body" => body},
         socket
       ) do
    case send_session_message(session_id, body) do
      {:ok, _session_id_int} ->
        {:halt, socket}

      {:error, reason} ->
        {:halt, push_event(socket, "config_guide_error", %{error: reason})}
    end
  end

  defp handle_fab_event("config_guide_close_chat", _params, socket) do
    {:halt, unsubscribe_config_guide_session(socket)}
  end

  defp handle_fab_event("start_config_guide_agent", _params, socket) do
    params = %{
      "instructions" => "Help me configure Claude Code.",
      "agent" => "claude-config-guide",
      "model" => "sonnet"
    }

    socket =
      case AgentManager.spawn_agent(params) do
        {:ok, %{session: session}} ->
          push_event(socket, "config_guide_agent_started", %{session_uuid: session.uuid})

        {:error, reason} ->
          Logger.error("ConfigGuide spawn failed: #{inspect(reason)}")
          push_event(socket, "config_guide_error", %{error: "Failed to start Config Guide"})
      end

    {:halt, socket}
  end

  defp handle_fab_event(_event, _params, socket) do
    {:cont, socket}
  end

  defp handle_fab_info(:fab_refresh_statuses, socket) do
    statuses = fetch_bookmark_statuses(socket.assigns.fab_bookmarks)

    socket =
      socket
      |> assign(:fab_statuses, statuses)
      |> schedule_fab_refresh()

    update_fab_component(socket)
    {:halt, socket}
  end

  # Shared session message router — routes to FAB chat or Config Guide chat by session_id.
  defp handle_fab_info(
         {:new_message,
          %EyeInTheSky.Messages.Message{
            session_id: session_id,
            sender_role: role,
            body: body
          } = msg},
         socket
       )
       when role != "user" do
    cond do
      session_id == socket.assigns.fab_active_session_id ->
        {:halt, push_event(socket, "fab_chat_message", %{body: body, sender_role: role})}

      session_id == socket.assigns.config_guide_active_session_id ->
        {:halt,
         push_event(socket, "config_guide_message", %{
           id: msg.id,
           session_id: session_id,
           body: body,
           sender_role: role,
           inserted_at: to_string(msg.inserted_at)
         })}

      true ->
        {:cont, socket}
    end
  end

  defp handle_fab_info({event, _}, socket)
       when event in [:notification_created, :notifications_updated, :notification_read] do
    send_update(EyeInTheSkyWeb.Components.Rail,
      id: "app-rail",
      notification_count: :refresh
    )

    {:halt, socket}
  end

  defp handle_fab_info({:project_updated, _project}, socket) do
    send_update(EyeInTheSkyWeb.Components.Rail,
      id: "app-rail",
      refresh_projects: true
    )

    {:halt, socket}
  end

  defp handle_fab_info({event, _channel}, socket)
       when event in [:channel_created, :channel_deleted] do
    send_update(EyeInTheSkyWeb.Components.Rail,
      id: "app-rail",
      refresh_channels: true
    )

    {:halt, socket}
  end

  defp handle_fab_info(_msg, socket) do
    {:cont, socket}
  end

  defp switch_active_session(socket, session_id) do
    socket = unsubscribe_active_session(socket)

    if socket.assigns.fab_active_session_id != session_id do
      EyeInTheSky.Events.subscribe_session(session_id)
    end

    assign(socket, :fab_active_session_id, session_id)
  end

  defp unsubscribe_active_session(socket) do
    case socket.assigns.fab_active_session_id do
      nil ->
        socket

      id ->
        EyeInTheSky.Events.unsubscribe_session(id)
        assign(socket, :fab_active_session_id, nil)
    end
  end

  defp unsubscribe_config_guide_session(socket) do
    case socket.assigns.config_guide_active_session_id do
      nil ->
        socket

      id ->
        EyeInTheSky.Events.unsubscribe_session(id)
        assign(socket, :config_guide_active_session_id, nil)
    end
  end

  # Schedules the next status poll, cancelling any outstanding timer first.
  # NOTE: on_mount hooks have no destroy/terminate callback. This timer fires
  # every @refresh_interval_ms until the consuming LiveView process exits — at
  # which point the process dies and all pending timers are discarded automatically.
  # Cancelling before each reschedule prevents accumulation when events arrive
  # faster than the interval.
  defp schedule_fab_refresh(socket) do
    if socket.assigns[:fab_timer], do: Process.cancel_timer(socket.assigns.fab_timer)
    timer = Process.send_after(self(), :fab_refresh_statuses, @refresh_interval_ms)
    assign(socket, :fab_timer, timer)
  end

  defp fetch_bookmark_statuses(bookmarks) when not is_list(bookmarks), do: %{}
  defp fetch_bookmark_statuses([]), do: %{}

  defp fetch_bookmark_statuses(bookmarks) do
    ids =
      Enum.map(bookmarks, fn
        b when is_binary(b) -> b
        b when is_integer(b) -> to_string(b)
        %{"session_id" => sid} when is_binary(sid) -> sid
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    if ids == [] do
      %{}
    else
      sessions = Sessions.list_sessions_by_mixed_ids(ids)

      sessions
      |> Enum.reduce(%{}, fn s, acc ->
        status = s.status || "idle"
        acc = Map.put(acc, to_string(s.id), status)
        if s.uuid, do: Map.put(acc, s.uuid, status), else: acc
      end)
    end
  end

  defp update_fab_component(socket) do
    send_update(EyeInTheSkyWeb.Components.FloatingChatComponent,
      id: "favorite-fab",
      bookmarks: socket.assigns.fab_bookmarks,
      statuses: socket.assigns.fab_statuses
    )
  end

  defp send_session_message(session_id, body) do
    result =
      Repo.transaction(fn ->
        with {:ok, session} <- Sessions.resolve(session_id),
             {:ok, _message} <-
               Messages.send_message(%{
                 session_id: session.id,
                 sender_role: "user",
                 recipient_role: "agent",
                 provider: "claude",
                 body: body
               }) do
          session
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, session} ->
        case AgentManager.continue_session(session.id, body, model: "sonnet") do
          {:ok, _} ->
            {:ok, session.id}

          {:error, reason} ->
            Logger.warning("FAB continue_session failed after message saved: #{inspect(reason)}")
            {:ok, session.id}
        end

      {:error, reason} ->
        Logger.error("FAB send_session_message error: #{inspect(reason)}")
        {:error, to_string(reason)}
    end
  end
end
