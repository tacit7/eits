defmodule EyeInTheSkyWeb.ChatLive do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{ChannelMessages, Channels, MessageReactions, Messages, Sessions}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Claude.ChannelProtocol
  alias EyeInTheSkyWeb.ChatLive.ChannelActions
  alias EyeInTheSkyWeb.ChatLive.ChannelDataLoader
  alias EyeInTheSkyWeb.ChatLive.ChannelHeader
  alias EyeInTheSkyWeb.ChatLive.ChannelHelpers
  alias EyeInTheSkyWeb.ChatPresenter
  alias EyeInTheSkyWeb.Helpers.SlashItems
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers
  import EyeInTheSkyWeb.Helpers.ChannelRoutingHelpers
  import EyeInTheSkyWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWeb.Helpers.UploadHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1, parse_int: 2]
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    session_id = Sessions.ensure_web_ui_session()

    if connected?(socket) do
      subscribe_agent_working()
    end

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:working_agents, %{})
      |> assign(:sidebar_tab, :chat)
      |> assign(:sidebar_project, nil)
      |> allow_upload(:agent_images,
        accept: ~w(.jpg .jpeg .png .gif .webp),
        max_entries: 5,
        max_file_size: 20_000_000,
        auto_upload: true
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, setup_channel(params, socket)}
  end

  defp setup_channel(params, socket) do
    {project_id, channel_id, channels} = resolve_channel(params, socket)
    load_channel_assigns(project_id, channel_id, channels, params, socket)
  end

  defp resolve_channel(params, socket) do
    project_id = get_project_id(params)
    channels = load_channels(project_id)
    channel_id = params["channel_id"] || get_default_channel_id(channels, project_id)
    {channel_id, channels} = ensure_default_channel(channel_id, channels, project_id, socket)

    if connected?(socket) && channel_id do
      subscribe_channel_messages(channel_id)
    end

    {project_id, channel_id, channels}
  end

  defp load_channel_assigns(project_id, channel_id, channels, params, socket) do
    data =
      ChannelDataLoader.load(project_id, channel_id, %{
        channels: channels,
        session_id: get_session_id(socket),
        session_search: socket.assigns[:session_search] || "",
        thread_id: params["thread_id"]
      })

    socket
    |> assign(:page_title, "Chat")
    |> assign(:project_id, project_id)
    |> assign(:all_projects, data.all_projects)
    |> assign(:channels, ChatPresenter.serialize_channels(channels))
    |> assign(:active_channel_id, channel_id)
    |> assign(:messages, data.messages)
    |> assign(:unread_counts, data.unread_counts)
    |> assign(:active_thread, data.active_thread)
    |> assign(:agent_status_counts, data.agent_status_counts)
    |> assign(:prompts, data.prompts)
    |> assign(:agent_templates, data.agent_templates)
    |> assign(:active_agents, data.active_sessions)
    |> assign(:channel_members, data.channel_members)
    |> assign(:sessions_by_project, data.sessions_by_project)
    |> assign(:show_agent_drawer, false)
    |> assign(:show_members, false)
    |> assign_new(:session_search, fn -> "" end)
    |> assign(:slash_items, SlashItems.build())
  end

  defp load_channels(project_id) do
    case Channels.list_channels_for_project(project_id) do
      channels when is_list(channels) -> channels
      _ -> []
    end
  end

  @impl true
  def handle_event("change_channel", %{"channel_id" => channel_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?channel_id=#{channel_id}")}
  end

  @impl true
  def handle_event("send_channel_message", %{"channel_id" => channel_id, "body" => body}, socket) do
    session_id = get_session_id(socket)
    content_blocks = consume_agent_images_as_content_blocks(socket)

    case ChannelMessages.send_channel_message(%{
           channel_id: channel_id,
           session_id: session_id,
           sender_role: "user",
           recipient_role: "agent",
           provider: "claude",
           body: body
         }) do
      {:ok, message} ->
        EyeInTheSky.Events.channel_message(channel_id, message)
        Channels.mark_as_read(channel_id, session_id)
        ChannelHelpers.route_to_members(channel_id, body, session_id, content_blocks)
        {:noreply, refresh_members_and_picker(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  @impl true
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
          channel = Channels.get_channel(channel_id)
          channel_ctx = %{id: channel.id, name: channel.name}
          prompt = ChannelProtocol.build_prompt(:direct, body, channel_ctx)

          AgentManager.send_message(target_session_id, prompt, channel_id: channel_id)
        end

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  @impl true
  def handle_event("add_agent_to_channel", params, socket),
    do: ChannelActions.handle_add_agent(socket, params)

  @impl true
  def handle_event("remove_agent_from_channel", params, socket),
    do: ChannelActions.handle_remove_agent(socket, params)

  @impl true
  def handle_event("open_thread", %{"message_id" => message_id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/chat?channel_id=#{socket.assigns.active_channel_id}&thread_id=#{message_id}"
     )}
  end

  @impl true
  def handle_event("close_thread", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?channel_id=#{socket.assigns.active_channel_id}")}
  end

  @impl true
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
      {:ok, message} ->
        EyeInTheSky.Events.channel_message(channel_id, message)
        active_thread = ChannelDataLoader.load_thread(parent_id)
        {:noreply, assign(socket, :active_thread, active_thread)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to send reply")}
    end
  end

  @impl true
  def handle_event("toggle_reaction", %{"message_id" => message_id, "emoji" => emoji}, socket) do
    session_id = get_session_id(socket)

    case MessageReactions.toggle_reaction(message_id, session_id, emoji) do
      {:ok, _action} ->
        {:noreply, assign(socket, :messages, reload_messages(socket))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to add reaction")}
    end
  end

  @impl true
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

  @impl true
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

  @impl true
  def handle_event("toggle_members", _params, socket) do
    {:noreply, assign(socket, :show_members, !socket.assigns.show_members)}
  end

  @impl true
  def handle_event("toggle_agent_drawer", _params, socket) do
    {:noreply, assign(socket, :show_agent_drawer, !socket.assigns.show_agent_drawer)}
  end

  @impl true
  def handle_event("validate_agent_upload", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_agent_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :agent_images, ref)}
  end

  @impl true
  def handle_event("create_channel", params, socket),
    do: ChannelActions.handle_create_channel(socket, params)

  @impl true
  def handle_event("create_agent", params, socket),
    do: ChannelActions.handle_create_agent(socket, params)

  @impl true
  def handle_info({:agent_working, msg}, socket) do
    AgentStatusHelpers.handle_agent_working(socket, msg, fn socket, session_id ->
      assign(socket, :working_agents, Map.put(socket.assigns.working_agents, session_id, true))
    end)
  end

  @impl true
  def handle_info({:agent_stopped, msg}, socket) do
    AgentStatusHelpers.handle_agent_stopped(socket, msg, fn socket, session_id ->
      assign(socket, :working_agents, Map.delete(socket.assigns.working_agents, session_id))
    end)
  end

  @impl true
  def handle_info({:new_message, _message}, socket) do
    Logger.info(
      "📨 Received new_message broadcast for channel #{socket.assigns.active_channel_id}"
    )

    messages = reload_messages(socket)

    Logger.info("📬 Loaded #{length(messages)} messages from DB")

    channels =
      case Channels.list_channels_for_project(socket.assigns.project_id) do
        channels when is_list(channels) -> channels
        _ -> []
      end

    unread_counts = ChannelHelpers.calculate_unread_counts(channels, get_session_id(socket))

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:unread_counts, unread_counts)}
  end

  @impl true
  def render(assigns) do
    active_channel =
      Enum.find(assigns.channels, fn c ->
        to_string(c.id) == to_string(assigns.active_channel_id)
      end)

    assigns = assign(assigns, :active_channel, active_channel)

    ~H"""
    <div class="flex flex-col h-[calc(100dvh-3rem)] md:h-[calc(100dvh-2rem)] px-4 sm:px-6 lg:px-8 py-4">
      <ChannelHeader.channel_header
        active_channel={@active_channel}
        agent_status_counts={@agent_status_counts}
        show_members={@show_members}
        channel_members={@channel_members}
        sessions_by_project={@sessions_by_project}
        session_search={@session_search}
      />
      <.message_feed
        active_channel_id={@active_channel_id}
        messages={@messages}
        active_agents={@active_agents}
        channel_members={@channel_members}
        working_agents={@working_agents}
        slash_items={@slash_items}
        socket={@socket}
      />
      <.agent_drawer
        show={@show_agent_drawer}
        all_projects={@all_projects}
        prompts={@prompts}
        agent_templates={@agent_templates}
        uploads={@uploads}
      />
    </div>
    """
  end

  # Sub-components

  defp message_feed(assigns) do
    ~H"""
    <div class="flex-1 min-h-0 max-w-6xl mx-auto w-full overflow-hidden">
      <.svelte
        name="AgentMessagesPanel"
        props={
          %{
            activeChannelId: @active_channel_id,
            messages: @messages,
            activeAgents: @active_agents,
            channelMembers: @channel_members,
            workingAgents: @working_agents,
            slashItems: @slash_items
          }
        }
        socket={@socket}
      />
    </div>
    """
  end

  defp agent_drawer(assigns) do
    ~H"""
    <.live_component
      module={EyeInTheSkyWeb.Components.NewSessionModal}
      id="new-session-modal"
      show={@show}
      toggle_event="toggle_agent_drawer"
      submit_event="create_agent"
      projects={@all_projects}
      current_project={nil}
      prompts={@prompts}
      agent_templates={@agent_templates}
      file_uploads={@uploads}
    />
    """
  end

  # Private helpers

  @default_project_id 1

  defp get_project_id(params) do
    parse_int(params["project_id"], @default_project_id)
  end

  defp get_default_channel_id(channels, _project_id) do
    case channels do
      [first | _] -> first.id
      [] -> nil
    end
  end

  defp ensure_default_channel(nil, [], project_id, socket) do
    session_id = get_session_id(socket)

    case Channels.create_default_channel(project_id, session_id) do
      {:ok, channel} ->
        channels = Channels.list_channels_for_project(project_id)
        {channel.id, channels}

      {:error, _} ->
        {nil, []}
    end
  end

  defp ensure_default_channel(channel_id, channels, _project_id, _socket) do
    {channel_id, channels}
  end

  defp get_session_id(socket) do
    socket.assigns[:session_id]
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

  defp reload_messages(socket) do
    ChannelMessages.list_messages_for_channel(socket.assigns.active_channel_id)
    |> ChatPresenter.serialize_messages()
  end
end
