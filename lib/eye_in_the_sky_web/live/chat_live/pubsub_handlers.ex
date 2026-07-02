defmodule EyeInTheSkyWeb.ChatLive.PubSubHandlers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias EyeInTheSky.ChannelMessages
  alias EyeInTheSky.Channels
  alias EyeInTheSkyWeb.ChatLive.ChannelHelpers
  alias EyeInTheSkyWeb.ChatPresenter
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers

  require Logger

  def handle_info({:agent_working, msg}, socket) do
    AgentStatusHelpers.handle_agent_working(socket, msg, fn socket, session_id ->
      socket
      |> assign(:working_agents, Map.put(socket.assigns.working_agents, session_id, true))
      |> assign(:active_stream_session_id, session_id)
    end)
  end

  def handle_info({:agent_stopped, msg}, socket) do
    AgentStatusHelpers.handle_agent_stopped(socket, msg, fn socket, session_id ->
      active = socket.assigns[:active_stream_session_id]

      socket
      |> assign(:working_agents, Map.delete(socket.assigns.working_agents, session_id))
      |> then(fn s ->
        if active == session_id, do: assign(s, :active_stream_session_id, nil), else: s
      end)
    end)
  end

  def handle_info({:agent_created, _}, socket), do: {:noreply, socket}
  def handle_info({:agent_updated, _}, socket), do: {:noreply, socket}
  def handle_info({:agent_deleted, _}, socket), do: {:noreply, socket}

  # Stream delta — text or tool_use
  def handle_info({:stream_delta, :text, text}, socket) do
    case socket.assigns[:active_stream_session_id] do
      nil ->
        {:noreply, socket}

      session_id ->
        new_content = (socket.assigns.stream_content || "") <> text

        {:noreply,
         socket
         |> assign(:stream_content, new_content)
         |> push_event("chat:stream_update", %{
           session_id: session_id,
           content: new_content,
           tool: socket.assigns.stream_tool
         })}
    end
  end

  def handle_info({:stream_delta, :tool_use, name}, socket) do
    case socket.assigns[:active_stream_session_id] do
      nil ->
        {:noreply, socket}

      session_id ->
        label = stream_tool_label(name)

        {:noreply,
         socket
         |> assign(:stream_tool, label)
         |> push_event("chat:stream_update", %{
           session_id: session_id,
           content: socket.assigns.stream_content || "",
           tool: label
         })}
    end
  end

  def handle_info({:stream_delta, _type, _content}, socket), do: {:noreply, socket}

  # Stream replace — full text replacement
  def handle_info({:stream_replace, :text, text}, socket) do
    case socket.assigns[:active_stream_session_id] do
      nil ->
        {:noreply, socket}

      session_id ->
        {:noreply,
         socket
         |> assign(:stream_content, text)
         |> push_event("chat:stream_update", %{
           session_id: session_id,
           content: text,
           tool: socket.assigns.stream_tool
         })}
    end
  end

  def handle_info({:stream_replace, _type, _content}, socket), do: {:noreply, socket}

  # Tool input label — e.g. "Bash: ls -la"
  def handle_info({:stream_tool_input, name, input}, socket) do
    case socket.assigns[:active_stream_session_id] do
      nil ->
        {:noreply, socket}

      session_id ->
        label = stream_tool_input_label(name, input)

        {:noreply,
         socket
         |> assign(:stream_tool, label)
         |> push_event("chat:stream_update", %{
           session_id: session_id,
           content: socket.assigns.stream_content || "",
           tool: label
         })}
    end
  end

  # Stream cleared — wipe state and notify Svelte
  def handle_info(:stream_clear, socket) do
    session_id = socket.assigns[:active_stream_session_id]

    socket =
      socket
      |> assign(:stream_content, "")
      |> assign(:stream_tool, nil)

    socket =
      if session_id do
        push_event(socket, "chat:stream_cleared", %{session_id: session_id})
      else
        socket
      end

    {:noreply, socket}
  end

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

      channels =
        case Channels.list_channels_for_project(socket.assigns.project_id) do
          channels when is_list(channels) -> channels
          _ -> []
        end
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

  defp stream_tool_label("command_execution"), do: "Bash"
  defp stream_tool_label("web_search"), do: "WebSearch"
  defp stream_tool_label("web_searches"), do: "WebSearch"
  defp stream_tool_label("mcp_tool_call"), do: "MCP Tool"
  defp stream_tool_label("mcp_tool_calls"), do: "MCP Tool"
  defp stream_tool_label(name) when is_binary(name), do: name
  defp stream_tool_label(_), do: "Tool"

  defp stream_tool_input_label(name, input) do
    base = stream_tool_label(name)

    case {name, input} do
      {"command_execution", %{} = map} ->
        command = get_input_field(map, "command") || ""
        if command == "", do: base, else: "#{base}: #{String.slice(command, 0, 60)}"

      {_, _} ->
        base
    end
  end

  defp get_input_field(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key) ||
      Enum.find_value(map, fn
        {k, v} when is_atom(k) ->
          if Atom.to_string(k) == key, do: v, else: nil

        _ ->
          nil
      end)
  end

  defp get_input_field(_map, _key), do: nil
end
