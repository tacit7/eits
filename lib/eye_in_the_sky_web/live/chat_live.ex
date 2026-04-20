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
    channels = load_channels(project_id)
    channel_id = params["channel_id"] || get_default_channel_id(channels, project_id)
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
      <nav class="w-[200px] flex-shrink-0 flex flex-col border-r border-base-content/8 bg-base-100" aria-label="Channels">
        <div class="px-2 pt-2 pb-1 border-b border-base-content/8">
          <button
            onclick="history.length > 1 ? history.back() : window.location.href = '/'"
            class="btn btn-ghost btn-xs px-1.5 self-center mr-1 text-base-content/50 hover:text-base-content"
            aria-label="Go back"
            title="Go back"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" />
          </button>
        </div>
        <div class="flex items-center justify-between px-3 pt-3 pb-1">
          <span class="text-[10px] font-bold uppercase tracking-widest text-base-content/30">Channels</span>
          <button phx-click="show_new_channel" class="text-base-content/30 hover:text-base-content/60 transition-colors leading-none text-base" title="New channel" aria-label="New channel">+</button>
        </div>
        <div class="flex-1 overflow-y-auto py-1">
          <%= for channel <- @channels do %>
            <.link
              navigate={~p"/chat?channel_id=#{channel.id}"}
              class={["flex items-center gap-1 px-2.5 py-1 mx-1.5 rounded text-sm transition-colors",
                if(not is_nil(@active_channel_id) && to_string(@active_channel_id) == to_string(channel.id),
                  do: "bg-primary/10 text-primary font-semibold",
                  else: "text-base-content/45 hover:text-base-content/70 hover:bg-base-content/5")]}
            >
              <span class="text-base-content/25 text-[13px]">#</span>{channel.name}
            </.link>
          <% end %>
          <%= if @new_channel_name do %>
            <form phx-submit="create_channel" phx-keydown="cancel_new_channel" class="flex items-center gap-1 px-2.5 mx-1.5 py-1">
              <span class="text-base-content/25 text-[13px]">#</span>
              <input type="text" name="name" value={@new_channel_name} phx-keyup="update_channel_name" placeholder="channel-name" class="flex-1 bg-transparent border-b border-base-content/15 text-sm text-base-content/70 placeholder:text-base-content/25 outline-none py-0.5 font-mono" autofocus />
            </form>
          <% else %>
            <button phx-click="show_new_channel" class="flex items-center gap-1 px-2.5 mx-1.5 py-1 text-sm text-base-content/30 hover:text-base-content/55 transition-colors w-full text-left">+ New Channel</button>
          <% end %>
        </div>
      </nav>
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

end
