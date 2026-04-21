defmodule EyeInTheSkyWeb.ChatLive do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Channels, Sessions}
  alias EyeInTheSkyWeb.ChatLive.ChannelDataLoader
  alias EyeInTheSkyWeb.ChatLive.ChannelHeader
  alias EyeInTheSkyWeb.ChatLive.EventHandlers
  alias EyeInTheSkyWeb.ChatLive.PubSubHandlers
  alias EyeInTheSkyWeb.ChatPresenter
  alias EyeInTheSkyWeb.Helpers.SlashItems
  import EyeInTheSkyWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 2]

  @impl true
  def mount(_params, _session, socket) do
    session_id = if connected?(socket), do: Sessions.ensure_web_ui_session(), else: nil

    if connected?(socket) do
      subscribe_agent_working()
    end

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:working_agents, %{})
      |> assign(:sidebar_tab, :chat)
      |> assign(:sidebar_project, nil)
      |> assign(:new_channel_name, nil)
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
    new_channel_id = params["channel_id"]
    current_channel_id = socket.assigns[:active_channel_id]

    channels =
      if new_channel_id != nil and current_channel_id != nil and
           to_string(new_channel_id) == to_string(current_channel_id) and
           socket.assigns[:project_id] == project_id do
        socket.assigns[:channels] || load_channels(project_id)
      else
        load_channels(project_id)
      end

    channel_id = new_channel_id || get_default_channel_id(channels, project_id)
    {channel_id, channels} = ensure_default_channel(channel_id, channels, project_id, socket)

    if connected?(socket) && channel_id do
      prev_channel_id = socket.assigns[:active_channel_id]

      if prev_channel_id && to_string(prev_channel_id) != to_string(channel_id) do
        unsubscribe_channel_messages(prev_channel_id)
      end

      unless prev_channel_id && to_string(prev_channel_id) == to_string(channel_id) do
        subscribe_channel_messages(channel_id)
      end
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
  def handle_event(event, params, socket), do: EventHandlers.handle_event(event, params, socket)

  @impl true
  def handle_info(msg, socket), do: PubSubHandlers.handle_info(msg, socket)

  @impl true
  def render(assigns) do
    active_channel =
      Enum.find(assigns.channels, fn c ->
        to_string(c.id) == to_string(assigns.active_channel_id)
      end)

    assigns = assign(assigns, :active_channel, active_channel)

    ~H"""
    <div class="flex h-[var(--app-viewport-height)] bg-base-100">
      <div class="flex-1 flex flex-col min-w-0">
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
    </div>
    """
  end

  # Sub-components

  defp message_feed(assigns) do
    ~H"""
    <div class="flex-1 min-h-0 overflow-hidden">
      <.svelte
        name="AgentMessagesPanel"
        ssr={false}
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

    if is_nil(session_id) do
      {nil, []}
    else
      case Channels.create_default_channel(project_id, session_id) do
        {:ok, channel} ->
          channels = Channels.list_channels_for_project(project_id)
          {channel.id, channels}

        {:error, _} ->
          {nil, []}
      end
    end
  end

  defp ensure_default_channel(channel_id, channels, _project_id, _socket) do
    {channel_id, channels}
  end

  defp get_session_id(socket) do
    socket.assigns[:session_id]
  end

end
