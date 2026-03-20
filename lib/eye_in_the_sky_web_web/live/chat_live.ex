defmodule EyeInTheSkyWebWeb.ChatLive do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{Agents, Channels, Messages, Projects, Prompts, Sessions}
  alias EyeInTheSkyWeb.Agents.AgentManager
  alias EyeInTheSkyWeb.Claude.ChannelProtocol
  alias EyeInTheSkyWebWeb.ChatPresenter
  import EyeInTheSkyWebWeb.Helpers.PubSubHelpers

  # Deterministic UUIDs for the web UI user
  @web_agent_uuid "00000000-0000-0000-0000-000000000001"
  @web_session_uuid "00000000-0000-0000-0000-000000000002"

  @impl true
  def mount(_params, _session, socket) do
    session_id = ensure_web_session()

    if connected?(socket) do
      subscribe_agent_working()
    end

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:working_agents, %{})
      |> assign(:sidebar_tab, :chat)
      |> assign(:sidebar_project, nil)

    {:ok, socket}
  end

  defp ensure_web_session do
    alias EyeInTheSkyWeb.{Agents, Sessions}

    case Sessions.get_session_by_uuid(@web_session_uuid) do
      {:ok, session} ->
        session.id

      {:error, :not_found} ->
        agent =
          case Agents.get_agent_by_uuid(@web_agent_uuid) do
            {:ok, a} ->
              a

            {:error, :not_found} ->
              {:ok, a} =
                Agents.create_agent(%{
                  uuid: @web_agent_uuid,
                  description: "Web UI User",
                  source: "web"
                })

              a
          end

        {:ok, session} =
          Sessions.create_session(%{
            uuid: @web_session_uuid,
            agent_id: agent.id,
            name: "Web UI",
            started_at: DateTime.utc_now() |> DateTime.to_iso8601()
          })

        session.id
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, load_channel_context(params, socket)}
  end

  defp load_channel_context(params, socket) do
    project_id = get_project_id(params)

    channels =
      case Channels.list_channels_for_project(project_id) do
        channels when is_list(channels) -> channels
        _ -> []
      end

    channel_id = params["channel_id"] || get_default_channel_id(channels, project_id)
    {channel_id, channels} = ensure_default_channel(channel_id, channels, project_id, socket)

    if connected?(socket) && channel_id do
      subscribe_channel_messages(channel_id)
    end

    messages =
      if channel_id do
        Messages.list_messages_for_channel(channel_id)
        |> ChatPresenter.serialize_messages()
      else
        []
      end

    unread_counts = calculate_unread_counts(channels, get_session_id(socket))
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

    channel_members = load_channel_members(channel_id)
    all_projects = Projects.list_projects()

    active_sessions =
      Sessions.list_active_sessions()
      |> EyeInTheSkyWeb.Repo.preload(:agent)
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
      ChatPresenter.build_sessions_by_project(channel_members, all_projects, session_search)

    socket
    |> assign(:page_title, "Chat")
    |> assign(:project_id, project_id)
    |> assign(:all_projects, all_projects)
    |> assign(:channels, ChatPresenter.serialize_channels(channels))
    |> assign(:active_channel_id, channel_id)
    |> assign(:messages, messages)
    |> assign(:unread_counts, unread_counts)
    |> assign(:active_thread, active_thread)
    |> assign(:agent_status_counts, agent_status_counts)
    |> assign(:prompts, prompts)
    |> assign(:agent_templates, agent_templates)
    |> assign(:active_agents, active_sessions)
    |> assign(:channel_members, channel_members)
    |> assign(:sessions_by_project, sessions_by_project)
    |> assign(:show_agent_drawer, false)
    |> assign(:show_members, false)
    |> assign_new(:session_search, fn -> "" end)
    |> assign(:slash_items, EyeInTheSkyWebWeb.Helpers.SlashItems.build())
  end

  @impl true
  def handle_event("change_channel", %{"channel_id" => channel_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?channel_id=#{channel_id}")}
  end

  @impl true
  def handle_event("send_channel_message", %{"channel_id" => channel_id, "body" => body}, socket) do
    require Logger
    session_id = get_session_id(socket)

    case Messages.send_channel_message(%{
           channel_id: channel_id,
           session_id: session_id,
           sender_role: "user",
           recipient_role: "agent",
           provider: "claude",
           body: body
         }) do
      {:ok, message} ->
        EyeInTheSkyWeb.Events.channel_message(channel_id, message)
        Channels.mark_as_read(channel_id, session_id)

        {_mode, mentioned_ids, _mention_all} = ChannelProtocol.parse_routing(body, -1)

        Enum.each(mentioned_ids, fn mid ->
          unless Channels.is_member?(channel_id, mid) do
            case Sessions.get_session(mid) do
              {:ok, s} ->
                Channels.add_member(channel_id, s.agent_id, mid)
                Logger.info("Auto-added session=#{mid} to channel=#{channel_id}")

              _ ->
                :ok
            end
          end
        end)

        agent_members = Channels.list_members(channel_id)

        Enum.each(agent_members, fn member ->
          unless ChannelProtocol.skip?(member.session_id, session_id) do
            {mode, _mentioned_ids, _mention_all} =
              ChannelProtocol.parse_routing(body, member.session_id)

            Messages.send_message(%{
              session_id: member.session_id,
              sender_role: "user",
              recipient_role: "agent",
              provider: "claude",
              body: body
            })

            prompt = ChannelProtocol.build_prompt(mode, body)
            Logger.info("Routing to session=#{member.session_id} mode=#{mode}")

            AgentManager.send_message(member.session_id, prompt,
              model: "sonnet",
              channel_id: channel_id
            )
          end
        end)

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

    target_session_id =
      case Integer.parse(to_string(target_session_id_str)) do
        {n, ""} -> n
        _ -> nil
      end

    case Messages.send_channel_message(%{
           channel_id: channel_id,
           session_id: session_id,
           sender_role: "user",
           recipient_role: "agent",
           provider: "claude",
           body: body
         }) do
      {:ok, message} ->
        EyeInTheSkyWeb.Events.channel_message(channel_id, message)

        if target_session_id do
          prompt = ChannelProtocol.build_prompt(:direct, body)
          AgentManager.send_message(target_session_id, prompt, channel_id: channel_id)
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
            Messages.send_channel_message(%{
              channel_id: channel_id,
              session_id: nil,
              sender_role: "system",
              recipient_role: "agent",
              provider: "system",
              body: "Agent @#{session_id} (#{session.name || "unnamed"}) joined the channel"
            })

          EyeInTheSkyWeb.Events.channel_message(channel_id, sys_msg)
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
        Messages.send_channel_message(%{
          channel_id: channel_id,
          session_id: nil,
          sender_role: "system",
          recipient_role: "agent",
          provider: "system",
          body: "Agent @#{session_id} (#{session.name || "unnamed"}) left the channel"
        })

      EyeInTheSkyWeb.Events.channel_message(channel_id, sys_msg)
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

    case Messages.create_thread_reply(parent_id, %{
           channel_id: channel_id,
           session_id: session_id,
           sender_role: "user",
           recipient_role: "agent",
           provider: "claude",
           body: body
         }) do
      {:ok, message} ->
        EyeInTheSkyWeb.Events.channel_message(channel_id, message)
        active_thread = load_thread(parent_id)
        {:noreply, assign(socket, :active_thread, active_thread)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to send reply")}
    end
  end

  @impl true
  def handle_event("toggle_reaction", %{"message_id" => message_id, "emoji" => emoji}, socket) do
    session_id = get_session_id(socket)

    case Messages.toggle_reaction(message_id, session_id, emoji) do
      {:ok, _action} ->
        messages =
          Messages.list_messages_for_channel(socket.assigns.active_channel_id)
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
      Messages.list_messages_for_channel(socket.assigns.active_channel_id)
      |> ChatPresenter.serialize_messages()

    {:noreply, assign(socket, :messages, messages)}
  end

  @impl true
  def handle_event("search_sessions", %{"session_search" => query}, socket) do
    sessions_by_project =
      ChatPresenter.build_sessions_by_project(
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
      Messages.send_channel_message(%{
        channel_id: channel_id,
        session_id: nil,
        sender_role: "system",
        recipient_role: "agent",
        provider: "system",
        body:
          "Creating new agent (#{model})#{if agent_name != "", do: " - #{agent_name}", else: ""}..."
      })

    instructions = if description != "", do: description, else: agent_description
    agent_type = params["agent_type"] || "claude"

    opts = [
      agent_type: agent_type,
      model: model,
      effort_level: effort_level,
      max_budget_usd: max_budget_usd,
      project_id: selected_project_id,
      project_path: project_path,
      description: agent_description,
      instructions: instructions,
      agent: params["agent"]
    ]

    case AgentManager.create_agent(opts) do
      {:ok, %{agent: agent, session: session}} ->
        if channel_id do
          case Channels.add_member(channel_id, agent.id, session.id) do
            {:ok, _member} ->
              {:ok, sys_msg} =
                Messages.send_channel_message(%{
                  channel_id: channel_id,
                  session_id: nil,
                  sender_role: "system",
                  recipient_role: "agent",
                  provider: "system",
                  body: "Agent @#{session.id} (#{agent_description}) joined the channel"
                })

              EyeInTheSkyWeb.Events.channel_message(channel_id, sys_msg)

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
  def handle_info({:agent_working, _session_uuid, session_int_id}, socket) do
    working_agents = Map.put(socket.assigns.working_agents, session_int_id, true)
    {:noreply, assign(socket, :working_agents, working_agents)}
  end

  @impl true
  def handle_info({:agent_working, %{id: session_int_id}}, socket) do
    working_agents = Map.put(socket.assigns.working_agents, session_int_id, true)
    {:noreply, assign(socket, :working_agents, working_agents)}
  end

  @impl true
  def handle_info({:agent_stopped, _session_uuid, session_int_id}, socket) do
    working_agents = Map.delete(socket.assigns.working_agents, session_int_id)
    {:noreply, assign(socket, :working_agents, working_agents)}
  end

  @impl true
  def handle_info({:agent_stopped, %{id: session_int_id}}, socket) do
    working_agents = Map.delete(socket.assigns.working_agents, session_int_id)
    {:noreply, assign(socket, :working_agents, working_agents)}
  end

  @impl true
  def handle_info({:new_message, _message}, socket) do
    require Logger

    Logger.info(
      "📨 Received new_message broadcast for channel #{socket.assigns.active_channel_id}"
    )

    messages =
      Messages.list_messages_for_channel(socket.assigns.active_channel_id)
      |> ChatPresenter.serialize_messages()

    Logger.info("📬 Loaded #{length(messages)} messages from DB")

    channels =
      case Channels.list_channels_for_project(socket.assigns.project_id) do
        channels when is_list(channels) -> channels
        _ -> []
      end

    unread_counts = calculate_unread_counts(channels, get_session_id(socket))

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
      <.channel_header
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
      />
    </div>
    """
  end

  # Sub-components

  defp channel_header(assigns) do
    ~H"""
    <div
      class="max-w-6xl mx-auto w-full bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl border border-base-content/5 shadow-sm mb-3 flex-shrink-0"
      id="chat-header-card"
    >
      <div class="px-5 py-3">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="w-2 h-2 rounded-full flex-shrink-0 bg-success animate-pulse" />
            <h1 class="text-lg font-bold text-base-content">
              <%= if @active_channel do %>
                <span class="text-base-content/30 mr-0.5">#</span>{@active_channel.name || "Channel"}
              <% else %>
                Chat
              <% end %>
            </h1>
            <%= if @active_channel && @active_channel[:description] do %>
              <span class="text-xs text-base-content/30">{@active_channel.description}</span>
            <% end %>
          </div>
          <div class="flex items-center gap-2">
            <%= if @agent_status_counts[:active] do %>
              <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-success/10 text-[11px] font-mono text-success">
                <span class="w-1.5 h-1.5 rounded-full bg-success"></span>
                {@agent_status_counts.active} active
              </span>
            <% end %>
            <%= if @agent_status_counts[:working] do %>
              <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-warning/10 text-[11px] font-mono text-warning">
                <span class="w-1.5 h-1.5 rounded-full bg-warning animate-pulse"></span>
                {@agent_status_counts.working} running
              </span>
            <% end %>
            <button
              phx-click="toggle_members"
              class={[
                "flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs transition-colors",
                if(@show_members,
                  do: "text-primary bg-primary/10 hover:bg-primary/15",
                  else: "text-base-content/40 hover:text-base-content/70 hover:bg-base-content/5"
                )
              ]}
            >
              <.icon name="hero-user-group-mini" class="w-3.5 h-3.5" />
              {length(@channel_members)} members
            </button>
            <button
              phx-click="toggle_agent_drawer"
              class="btn btn-xs btn-primary gap-1"
            >
              <.icon name="hero-plus-mini" class="w-3 h-3" /> New Agent
            </button>
          </div>
        </div>
      </div>

      <%= if @show_members do %>
        <.member_panel
          channel_members={@channel_members}
          sessions_by_project={@sessions_by_project}
          session_search={@session_search}
        />
      <% end %>
    </div>
    """
  end

  defp member_panel(assigns) do
    ~H"""
    <div class="px-5 pb-3 border-t border-base-content/5 pt-3" id="chat-members-panel">
      <div class="flex items-center justify-between mb-2">
        <span class="text-[10px] uppercase tracking-wider font-medium text-base-content/30">
          Channel Agents
        </span>
      </div>

      <%= if @channel_members != [] do %>
        <div class="flex flex-wrap gap-1.5 mb-3">
          <%= for member <- @channel_members do %>
            <div class="inline-flex items-center gap-0.5 group">
              <a
                href={~p"/dm/#{member.session_id}"}
                class="inline-flex items-center gap-1 font-mono text-[11px] font-medium px-2 py-0.5 rounded-l bg-base-content/[0.04] text-base-content/50 hover:text-primary hover:bg-primary/5 transition-colors border border-transparent hover:border-primary/10"
                title={"Session ##{member.session_id}"}
              >
                @{member.session_id}
                <%= if member.session_name do %>
                  <span class="text-base-content/35">
                    {String.slice(member.session_name, 0, 15)}{if String.length(
                                                                    member.session_name
                                                                  ) > 15, do: "…"}
                  </span>
                <% end %>
              </a>
              <button
                phx-click="remove_agent_from_channel"
                phx-value-session_id={member.session_id}
                class="inline-flex items-center px-1 py-0.5 rounded-r bg-base-content/[0.04] text-base-content/20 hover:text-error hover:bg-error/10 transition-colors border border-transparent opacity-0 group-hover:opacity-100"
                title="Remove from channel"
              >
                <.icon name="hero-x-mark" class="w-2.5 h-2.5" />
              </button>
            </div>
          <% end %>
        </div>
      <% else %>
        <p class="text-xs text-base-content/30 mb-3">
          No agents in this channel yet.
        </p>
      <% end %>

      <div class="border-t border-base-content/5 pt-2 mt-1">
        <div class="flex items-center justify-between mb-1.5">
          <span class="text-[10px] uppercase tracking-wider font-medium text-base-content/30">
            Add Agent
          </span>
        </div>
        <form phx-change="search_sessions" class="mb-2">
          <input
            type="text"
            name="session_search"
            value={@session_search}
            placeholder="Search sessions..."
            class="w-full input input-xs bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 text-xs"
            autocomplete="off"
            phx-debounce="200"
          />
        </form>
        <%= if @sessions_by_project != [] do %>
          <div class="max-h-48 overflow-y-auto space-y-2">
            <%= for group <- @sessions_by_project do %>
              <div>
                <span class="text-[10px] font-medium text-base-content/25 uppercase tracking-wider">
                  {group.project_name}
                </span>
                <div class="flex flex-wrap gap-1 mt-0.5">
                  <%= for session <- group.sessions do %>
                    <button
                      phx-click="add_agent_to_channel"
                      phx-value-session_id={session.id}
                      class="inline-flex items-center gap-1 font-mono text-[11px] px-2 py-0.5 rounded bg-base-content/[0.03] text-base-content/40 hover:text-primary hover:bg-primary/5 transition-colors border border-transparent hover:border-primary/10"
                      title={"Add @#{session.id} to channel"}
                    >
                      <.icon name="hero-plus-mini" class="w-2.5 h-2.5 opacity-50" />
                      @{session.id}
                      <span class="text-base-content/25">
                        {String.slice(session.name || session.agent_description || "", 0, 20)}{if String.length(
                                                                                                    session.name ||
                                                                                                      session.agent_description ||
                                                                                                      ""
                                                                                                  ) >
                                                                                                    20,
                                                                                                  do:
                                                                                                    "…"}
                      </span>
                      <span class="text-[9px] text-base-content/15">{session.model}</span>
                      <%= if session.ended_at do %>
                        <span class="text-[9px] text-base-content/15">ended</span>
                      <% end %>
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <p class="text-xs text-base-content/25 py-1">
            <%= if @session_search != "" do %>
              No sessions match "{@session_search}"
            <% else %>
              No available sessions
            <% end %>
          </p>
        <% end %>
      </div>
    </div>
    """
  end

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
      module={EyeInTheSkyWebWeb.Components.NewSessionModal}
      id="new-session-modal"
      show={@show}
      toggle_event="toggle_agent_drawer"
      submit_event="create_agent"
      projects={@all_projects}
      current_project={nil}
      prompts={@prompts}
      agent_templates={@agent_templates}
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
    parent_message = Messages.get_message_with_thread!(message_id)

    %{
      parent_message: ChatPresenter.serialize_message(parent_message),
      replies: Enum.map(parent_message.thread_replies, &ChatPresenter.serialize_message/1)
    }
  end

  defp calculate_unread_counts(channels, session_id) do
    Enum.reduce(channels, %{}, fn channel, acc ->
      count = Channels.count_unread_messages(channel.id, session_id)
      Map.put(acc, channel.id, count)
    end)
  end

  defp load_channel_members(nil), do: []

  defp load_channel_members(channel_id) do
    Channels.list_members(channel_id)
    |> Enum.map(fn member ->
      session_data =
        case Sessions.get_session(member.session_id) do
          {:ok, s} -> s
          _ -> nil
        end

      %{
        id: member.id,
        session_id: member.session_id,
        agent_id: member.agent_id,
        role: member.role,
        joined_at: member.joined_at,
        session_name: session_data && session_data.name,
        session_uuid: session_data && session_data.uuid
      }
    end)
  end

  defp refresh_members_and_picker(socket) do
    channel_id = socket.assigns.active_channel_id
    channel_members = load_channel_members(channel_id)
    search = socket.assigns[:session_search] || ""

    sessions_by_project =
      ChatPresenter.build_sessions_by_project(channel_members, socket.assigns.all_projects, search)

    socket
    |> assign(:channel_members, channel_members)
    |> assign(:sessions_by_project, sessions_by_project)
  end

  defp parse_budget(nil), do: nil
  defp parse_budget(""), do: nil

  defp parse_budget(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} when f > 0 -> f
      _ -> nil
    end
  end
end
