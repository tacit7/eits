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
    socket =
      socket
      |> assign(:fab_mounted, true)
      |> assign(:fab_timer, nil)
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

  defp handle_fab_event("fab_send_message", %{"session_id" => session_id, "body" => body}, socket) do
    case send_agent_message(session_id, body) do
      :ok ->
        {:halt, socket}

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

  defp handle_fab_info(_msg, socket) do
    {:cont, socket}
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
      :ok
    else
      {:error, reason} ->
        Logger.error("FAB chat error: #{inspect(reason)}")
        {:error, to_string(reason)}
    end
  end

  defp resolve_session(session_id) do
    case Integer.parse(session_id) do
      {id, ""} -> Sessions.get_session(id)
      _ -> Sessions.get_session(session_id)
    end
  end

  defp find_global_channel(project_id) do
    channels =
      if project_id,
        do: Channels.list_channels_for_project(project_id),
        else: Channels.list_channels()

    case Enum.find(channels, fn c -> c.name == "#global" end) do
      nil -> {:error, "Global channel not found"}
      channel -> {:ok, channel}
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
