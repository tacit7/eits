defmodule EyeInTheSkyWeb.ChatLive do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Agents, ChannelMessages, Channels, MessageReactions, Messages, Projects, Prompts, Sessions}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Claude.ChannelProtocol
  alias EyeInTheSkyWeb.ChatPresenter
  alias EyeInTheSkyWeb.ChatLive.ChannelHeader
  alias EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers
  alias EyeInTheSkyWeb.ChatLive.ChannelHelpers
  import EyeInTheSkyWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [parse_budget: 1]
  import EyeInTheSkyWeb.Helpers.UploadHelpers

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
    project_id = get_project_id(params)
    channels = load_channels(project_id)
    channel_id = params["channel_id"] || get_default_channel_id(channels, project_id)
    {channel_id, channels} = ensure_default_channel(channel_id, channels, project_id, socket)

    if connected?(socket) && channel_id do
      subscribe_channel_messages(channel_id)
    end

    data = load_channel_data(project_id, channel_id, params, socket)

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
    |> assign(:slash_items, EyeInTheSkyWeb.Helpers.SlashItems.build())
  end

  defp load_channels(project_id) do
    case Channels.list_channels_for_project(project_id) do
      channels when is_list(channels) -> channels
      _ -> []
    end
  end

  # Loads all DB data needed for the channel view. Extracted from setup_channel
  # to isolate side-effectful queries from socket assignment.
  defp load_channel_data(project_id, channel_id, params, socket) do
    messages =
      if channel_id do
        ChannelMessages.list_messages_for_channel(channel_id)
        |> ChatPresenter.serialize_messages()
      else
        []
      end

    channels = load_channels(project_id)
    unread_counts = ChannelHelpers.calculate_unread_counts(channels, get_session_id(socket))
    active_thread = load_thread(params["thread_id"])

    agent_status_counts =
      case Agents.get_agent_status_counts(project_id) do
        counts when is_map(counts) -> counts
        _ -> %{}
      end

    prompts =
      Prompts.list_prompts(project_id: project_id)
      |> ChatPresenter.serialize_prompts()

    agent_templates =
      Agents.list_active_agents()
      |> Enum.filter(fn a -> a.description && a.description != "" end)
      |> Enum.take(50)
      |> Enum.map(fn a -> %{id: a.id, description: a.description} end)

    channel_members = ChannelHelpers.load_channel_members(channel_id)
    all_projects = Projects.list_projects()

    active_sessions =
      Sessions.list_active_sessions()
      |> EyeInTheSky.Repo.preload(:agent)
      |> Enum.map(fn session ->
        %{
          id: session.id,
          uuid: session.uuid,
          name: session.name,
          description: session.description,
          provider: session.provider || "claude",
          model: session.model,
          project_id: session.project_id,
          agent_description:
            if(Ecto.assoc_loaded?(session.agent) && session.agent,
              do: session.agent.description,
              else: nil
            )
        }
      end)

    session_search = socket.assigns[:session_search] || ""

    sessions_by_project =
      ChannelHelpers.build_sessions_by_project(channel_members, all_projects, session_search)

    %{
      messages: messages,
      unread_counts: unread_counts,
      active_thread: active_thread,
      agent_status_counts: agent_status_counts,
      prompts: prompts,
      agent_templates: agent_templates,
      channel_members: channel_members,
      all_projects: all_projects,
      active_sessions: active_sessions,
      sessions_by_project: sessions_by_project
    }
  end

  @impl true
  def handle_event("change_channel", %{"channel_id" => channel_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?channel_id=#{channel_id}")}
  end

  @impl true
  def handle_event("send_channel_message", %{"channel_id" => channel_id, "body" => body}, socket) do
    require Logger
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
    require Logger
    session_id = get_session_id(socket)
    channel_id = params["channel_id"] || socket.assigns.active_channel_id
    content_blocks = consume_agent_images_as_content_blocks(socket)

    target_session_id =
      case Integer.parse(to_string(target_session_id_str)) do
        {n, ""} -> n
        _ -> nil
      end

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

        if target_session_id do
          prompt = ChannelProtocol.build_prompt(:direct, body)

          AgentManager.send_message(target_session_id, prompt,
            channel_id: channel_id,
            content_blocks: content_blocks
          )
        end

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
    end
  end

  @impl true
  def handle_event("add_agent_to_channel", %{"session_id" => session_id_str}, socket) do
    require Logger
    channel_id = socket.assigns.active_channel_id

    with {session_id, ""} <- Integer.parse(session_id_str),
         {:ok, session} <- Sessions.get_session(session_id) do
      agent_id = session.agent_id

      case Channels.add_member(channel_id, agent_id, session_id) do
        {:ok, _member} ->
          {:ok, sys_msg} =
            ChannelMessages.send_channel_message(%{
              channel_id: channel_id,
              session_id: nil,
              sender_role: "system",
              recipient_role: "agent",
              provider: "system",
              body: "Agent @#{session_id} (#{session.name || "unnamed"}) joined the channel"
            })

          EyeInTheSky.Events.channel_message(channel_id, sys_msg)
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

  @impl true
  def handle_event("remove_agent_from_channel", %{"session_id" => session_id_str}, socket) do
    require Logger
    channel_id = socket.assigns.active_channel_id

    with {session_id, ""} <- Integer.parse(session_id_str),
         {:ok, session} <- Sessions.get_session(session_id) do
      Channels.remove_member(channel_id, session_id)

      {:ok, sys_msg} =
        ChannelMessages.send_channel_message(%{
          channel_id: channel_id,
          session_id: nil,
          sender_role: "system",
          recipient_role: "agent",
          provider: "system",
          body: "Agent @#{session_id} (#{session.name || "unnamed"}) left the channel"
        })

      EyeInTheSky.Events.channel_message(channel_id, sys_msg)
      Logger.info("Removed agent session=#{session_id} from channel=#{channel_id}")

      {:noreply, refresh_members_and_picker(socket)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid session ID")}
    end
  end

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
        active_thread = load_thread(parent_id)
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
        messages =
          ChannelMessages.list_messages_for_channel(socket.assigns.active_channel_id)
          |> ChatPresenter.serialize_messages()

        {:noreply, assign(socket, :messages, messages)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to add reaction")}
    end
  end

  @impl true
  def handle_event("delete_message", %{"id" => id_str}, socket) do
    {id, ""} = Integer.parse(id_str)
    message = Messages.get_message!(id)
    {:ok, _} = Messages.delete_message(message)

    messages =
      ChannelMessages.list_messages_for_channel(socket.assigns.active_channel_id)
      |> ChatPresenter.serialize_messages()

    {:noreply, assign(socket, :messages, messages)}
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
  def handle_event("create_channel", _params, socket) do
    {:noreply, put_flash(socket, :info, "Channel creation coming soon")}
  end

  @impl true
  def handle_event("create_agent", params, socket) do
    model = params["model"] || "sonnet"
    effort_level = params["effort_level"]
    max_budget_usd = parse_budget(params["max_budget_usd"])
    agent_name = params["agent_name"] || ""
    description = params["description"] || ""
    selected_project_id = params["project_id"]
    channel_id = socket.assigns.active_channel_id

    selected_project =
      Enum.find(socket.assigns.all_projects, fn p ->
        to_string(p.id) == to_string(selected_project_id)
      end)

    project_path = if selected_project, do: selected_project.path, else: File.cwd!()

    agent_description =
      if agent_name != "" do
        agent_name
      else
        "Channel agent for #{channel_id}"
      end

    {:ok, _creating_msg} =
      ChannelMessages.send_channel_message(%{
        channel_id: channel_id,
        session_id: nil,
        sender_role: "system",
        recipient_role: "agent",
        provider: "system",
        body:
          "Creating new agent (#{model})#{if agent_name != "", do: " - #{agent_name}", else: ""}..."
      })

    base_instructions = if description != "", do: description, else: agent_description
    uploaded_images = consume_agent_images(socket)
    instructions = append_image_paths(base_instructions, uploaded_images)
    agent_type = params["agent_type"] || "claude"

    advanced_opts =
      []
      |> maybe_opt(:permission_mode, params["permission_mode"])
      |> maybe_int_opt(:max_turns, params["max_turns"])
      |> maybe_opt(:add_dir, params["add_dir"])
      |> maybe_opt(:mcp_config, params["mcp_config"])
      |> maybe_opt(:plugin_dir, params["plugin_dir"])
      |> maybe_opt(:settings_file, params["settings_file"])
      |> maybe_bool_opt(:chrome, params["chrome"])
      |> maybe_bool_opt(:sandbox, params["sandbox"])

    opts =
      [
        agent_type: agent_type,
        model: model,
        effort_level: effort_level,
        max_budget_usd: max_budget_usd,
        project_id: selected_project_id,
        project_path: project_path,
        description: agent_description,
        instructions: instructions,
        agent: params["agent"]
      ] ++ advanced_opts

    case AgentManager.create_agent(opts) do
      {:ok, %{agent: agent, session: session}} ->
        if channel_id do
          case Channels.add_member(channel_id, agent.id, session.id) do
            {:ok, _member} ->
              {:ok, sys_msg} =
                ChannelMessages.send_channel_message(%{
                  channel_id: channel_id,
                  session_id: nil,
                  sender_role: "system",
                  recipient_role: "agent",
                  provider: "system",
                  body: "Agent @#{session.id} (#{agent_description}) joined the channel"
                })

              EyeInTheSky.Events.channel_message(channel_id, sys_msg)

            {:error, _} ->
              :ok
          end
        end

        {:noreply,
         socket
         |> assign(:show_agent_drawer, false)
         |> refresh_members_and_picker()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:show_agent_drawer, false)
         |> put_flash(:error, "Failed to create agent: #{inspect(reason)}")}
    end
  end

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
    require Logger

    Logger.info(
      "📨 Received new_message broadcast for channel #{socket.assigns.active_channel_id}"
    )

    messages =
      ChannelMessages.list_messages_for_channel(socket.assigns.active_channel_id)
      |> ChatPresenter.serialize_messages()

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

  defp get_project_id(params) do
    case params["project_id"] do
      nil ->
        1

      project_id when is_binary(project_id) ->
        case Integer.parse(project_id) do
          {int, ""} -> int
          {_int, _rest} -> 1
          :error -> 1
        end

      project_id when is_integer(project_id) ->
        project_id

      _project_id ->
        1
    end
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

  defp load_thread(nil), do: nil

  defp load_thread(message_id) do
    parent_message = ChannelMessages.get_message_with_thread!(message_id)

    %{
      parent_message: ChatPresenter.serialize_message(parent_message),
      replies: Enum.map(parent_message.thread_replies, &ChatPresenter.serialize_message/1)
    }
  end

  defp refresh_members_and_picker(socket) do
    channel_id = socket.assigns.active_channel_id
    channel_members = ChannelHelpers.load_channel_members(channel_id)
    search = socket.assigns[:session_search] || ""

    sessions_by_project =
      ChannelHelpers.build_sessions_by_project(channel_members, socket.assigns.all_projects, search)

    socket
    |> assign(:channel_members, channel_members)
    |> assign(:sessions_by_project, sessions_by_project)
  end

  defp maybe_opt(opts, _key, nil), do: opts
  defp maybe_opt(opts, _key, ""), do: opts
  defp maybe_opt(opts, key, val), do: opts ++ [{key, val}]

  defp maybe_int_opt(opts, _key, nil), do: opts
  defp maybe_int_opt(opts, _key, ""), do: opts

  defp maybe_int_opt(opts, key, val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n > 0 -> opts ++ [{key, n}]
      _ -> opts
    end
  end

  defp maybe_bool_opt(opts, _key, nil), do: opts
  defp maybe_bool_opt(opts, key, "true"), do: opts ++ [{key, true}]
  defp maybe_bool_opt(opts, _key, _), do: opts

end
