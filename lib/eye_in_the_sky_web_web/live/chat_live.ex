defmodule EyeInTheSkyWebWeb.ChatLive do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{Agents, Channels, Messages, Projects, Prompts, Sessions}
  alias EyeInTheSkyWeb.Claude.AgentManager

  # Deterministic UUIDs for the web UI user
  @web_agent_uuid "00000000-0000-0000-0000-000000000001"
  @web_session_uuid "00000000-0000-0000-0000-000000000002"

  @impl true
  def mount(_params, _session, socket) do
    session_id = ensure_web_session()

    # Subscribe to agent working events once on mount
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "agent:working")
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
        # Create the web UI agent first
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
    # Get project_id from params or default to first project
    project_id = get_project_id(params)

    # Load channels for this project (with error handling for invalid IDs)
    channels =
      case Channels.list_channels_for_project(project_id) do
        channels when is_list(channels) -> channels
        _ -> []
      end

    # Determine active channel (from URL or first channel)
    channel_id = params["channel_id"] || get_default_channel_id(channels, project_id)

    # Create default channel if none exists
    {channel_id, channels} = ensure_default_channel(channel_id, channels, project_id, socket)

    # Subscribe to channel messages if connected
    if connected?(socket) && channel_id do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "channel:#{channel_id}:messages")
    end

    # Load messages for active channel (with JSONL support)
    messages =
      if channel_id do
        # First try to load from JSONL files (opcode-style), fall back to database
        channel_messages = Messages.list_messages_for_channel(channel_id)

        # For JSONL storage, get project_id as string (will be set in socket in handle_params)
        # For now, just use database messages
        channel_messages
        |> serialize_messages()
      else
        []
      end

    # Calculate unread counts for all channels
    unread_counts = calculate_unread_counts(channels, get_session_id(socket))

    # Load active thread if specified
    active_thread = load_thread(params["thread_id"])

    # Get agent status counts for the project (with error handling)
    agent_status_counts =
      case Agents.get_agent_status_counts(project_id) do
        counts when is_map(counts) -> counts
        _ -> %{}
      end

    # Load available prompts for agent creation
    # Convert project_id to string since prompts table uses string project_id
    prompts =
      Prompts.list_prompts(project_id: project_id)
      |> serialize_prompts()

    # Load channel members
    channel_members = load_channel_members(channel_id)

    # Load active sessions for @ autocomplete
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
          agent_description:
            if(Ecto.assoc_loaded?(session.agent) && session.agent,
              do: session.agent.description,
              else: nil
            )
        }
      end)

    # Load all projects for the session drawer
    all_projects = Projects.list_projects()

    socket =
      socket
      |> assign(:page_title, "Chat")
      |> assign(:project_id, project_id)
      |> assign(:all_projects, all_projects)
      |> assign(:channels, serialize_channels(channels))
      |> assign(:active_channel_id, channel_id)
      |> assign(:messages, messages)
      |> assign(:unread_counts, unread_counts)
      |> assign(:active_thread, active_thread)
      |> assign(:agent_status_counts, agent_status_counts)
      |> assign(:prompts, prompts)
      |> assign(:active_agents, active_sessions)
      |> assign(:channel_members, channel_members)
      |> assign(:show_agent_drawer, false)
      |> assign(:show_members, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_channel", %{"channel_id" => channel_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?channel_id=#{channel_id}")}
  end

  @impl true
  def handle_event("send_channel_message", %{"channel_id" => channel_id, "body" => body}, socket) do
    require Logger
    session_id = get_session_id(socket)

    # 1. Save user message to channel
    case Messages.send_channel_message(%{
           channel_id: channel_id,
           session_id: session_id,
           sender_role: "user",
           recipient_role: "agent",
           provider: "claude",
           body: body
         }) do
      {:ok, message} ->
        # 2. Broadcast to channel PubSub
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "channel:#{channel_id}:messages",
          {:new_message, message}
        )

        # Mark channel as read
        Channels.mark_as_read(channel_id, session_id)

        # 3. Parse @mentions from body
        mention_all = Regex.match?(~r/@all\b/i, body)

        mentioned_ids =
          Regex.scan(~r/@(\d+)/, body)
          |> Enum.map(fn [_, id_str] ->
            case Integer.parse(id_str) do
              {id, ""} -> id
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        # 4. Auto-add mentioned sessions that aren't channel members yet
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

        # 5. Get all agent members of this channel (now includes auto-added)
        agent_members = Channels.list_members(channel_id)

        # 6. Route message to each agent member (skip the sending user to avoid spam)
        Enum.each(agent_members, fn member ->
          unless member.session_id == session_id do
            is_mentioned = mention_all or member.session_id in mentioned_ids

            prompt =
              if is_mentioned do
                "CHANNEL_RESPOND: You were @mentioned. Respond to: #{body}"
              else
                "CHANNEL_OBSERVE: Only respond if you have relevant input. If nothing to add, respond with exactly [NO_RESPONSE]. Message: #{body}"
              end

            # Save a copy of the user's message to the agent's session
            # so the DM page shows the full conversation
            Messages.send_message(%{
              session_id: member.session_id,
              channel_id: channel_id,
              sender_role: "user",
              recipient_role: "agent",
              provider: "claude",
              body: body
            })

            Logger.info("Routing to agent session=#{member.session_id} mentioned=#{is_mentioned}")

            AgentManager.send_message(member.session_id, prompt,
              model: "sonnet",
              channel_id: channel_id
            )
          end
        end)

        # Reload channel members in assigns (in case auto-added)
        channel_members = load_channel_members(channel_id)
        {:noreply, assign(socket, :channel_members, channel_members)}

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
          # Broadcast system message to channel
          {:ok, sys_msg} =
            Messages.send_channel_message(%{
              channel_id: channel_id,
              session_id: nil,
              sender_role: "system",
              recipient_role: "agent",
              provider: "system",
              body: "Agent @#{session_id} (#{session.name || "unnamed"}) joined the channel"
            })

          Phoenix.PubSub.broadcast(
            EyeInTheSkyWeb.PubSub,
            "channel:#{channel_id}:messages",
            {:new_message, sys_msg}
          )

          # Reload channel members
          channel_members = load_channel_members(channel_id)
          Logger.info("Added agent session=#{session_id} to channel=#{channel_id}")

          {:noreply, assign(socket, :channel_members, channel_members)}

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
        # Broadcast to channel subscribers
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "channel:#{channel_id}:messages",
          {:new_message, message}
        )

        # Reload thread
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
        # Reload messages to show updated reactions
        messages =
          Messages.list_messages_for_channel(socket.assigns.active_channel_id)
          |> serialize_messages()

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
      |> serialize_messages()

    {:noreply, assign(socket, :messages, messages)}
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
    # TODO: Open modal or navigate to channel creation page
    {:noreply, put_flash(socket, :info, "Channel creation coming soon")}
  end

  @impl true
  def handle_event("create_agent", params, socket) do
    model = params["model"] || "sonnet"
    effort_level = params["effort_level"]
    agent_name = params["agent_name"] || ""
    description = params["description"] || ""
    selected_project_id = params["project_id"]
    channel_id = socket.assigns.active_channel_id

    # Look up the selected project's path
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

    # Send system notification to channel
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

    # Use description as initial instructions, fall back to agent name
    instructions = if description != "", do: description, else: agent_description

    # Delegate to AgentManager for full lifecycle
    agent_type = params["agent_type"] || "claude"

    opts = [
      agent_type: agent_type,
      model: model,
      effort_level: effort_level,
      project_id: selected_project_id,
      project_path: project_path,
      description: agent_description,
      instructions: instructions
    ]

    case AgentManager.create_agent(opts) do
      {:ok, %{agent: agent, session: session}} ->
        # Auto-add the new agent to the current channel
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

              Phoenix.PubSub.broadcast(
                EyeInTheSkyWeb.PubSub,
                "channel:#{channel_id}:messages",
                {:new_message, sys_msg}
              )

            {:error, _} ->
              :ok
          end
        end

        channel_members = load_channel_members(channel_id)

        {:noreply,
         socket
         |> assign(:show_agent_drawer, false)
         |> assign(:channel_members, channel_members)}

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

  # Handle struct variant from PubSub
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

    # Reload messages when new message arrives via PubSub
    messages =
      Messages.list_messages_for_channel(socket.assigns.active_channel_id)
      |> serialize_messages()

    Logger.info("📬 Loaded #{length(messages)} messages from DB")

    # Update unread counts (with error handling)
    channels =
      case Channels.list_channels_for_project(socket.assigns.project_id) do
        channels when is_list(channels) -> channels
        _ -> []
      end

    unread_counts = calculate_unread_counts(channels, get_session_id(socket))

    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:unread_counts, unread_counts)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    active_channel =
      Enum.find(assigns.channels, fn c ->
        to_string(c.id) == to_string(assigns.active_channel_id)
      end)

    assigns = assign(assigns, :active_channel, active_channel)

    ~H"""
    <div class="flex flex-col h-[calc(100vh-2rem)] px-4 sm:px-6 lg:px-8 py-4">
      <%!-- Header card --%>
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
              <%!-- Status pills --%>
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
                <.icon name="hero-plus-mini" class="w-3 h-3" /> Agent
              </button>
            </div>
          </div>
        </div>

        <%!-- Members panel (collapsible, server-rendered) --%>
        <%= if @show_members do %>
          <div class="px-5 pb-3 border-t border-base-content/5 pt-3" id="chat-members-panel">
            <div class="flex items-center justify-between mb-2">
              <span class="text-[10px] uppercase tracking-wider font-medium text-base-content/30">
                Channel Agents
              </span>
            </div>

            <%= if @channel_members != [] do %>
              <div class="flex flex-wrap gap-1.5 mb-3">
                <%= for member <- @channel_members do %>
                  <a
                    href={~p"/dm/#{member.session_id}"}
                    class="inline-flex items-center gap-1 font-mono text-[11px] font-medium px-2 py-0.5 rounded bg-base-content/[0.04] text-base-content/50 hover:text-primary hover:bg-primary/5 transition-colors border border-transparent hover:border-primary/10"
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
                <% end %>
              </div>
            <% else %>
              <p class="text-xs text-base-content/30 mb-3">
                No agents in this channel yet. Add one by session ID or spawn a new one.
              </p>
            <% end %>

            <%!-- Add agent by session ID --%>
            <form phx-submit="add_agent_to_channel" class="flex gap-1.5" id="add-agent-form">
              <input
                type="text"
                name="session_id"
                placeholder="Session ID to add..."
                class="flex-1 input input-xs bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 font-mono text-xs"
                autocomplete="off"
                id="add-agent-session-id"
              />
              <button type="submit" class="btn btn-xs btn-primary">Add</button>
            </form>
          </div>
        <% end %>
      </div>

      <%!-- Messages panel (Svelte: messages + @autocomplete input only) --%>
      <div class="flex-1 min-h-0 max-w-6xl mx-auto w-full overflow-hidden">
        <.svelte
          name="AgentMessagesPanel"
          props={
            %{
              activeChannelId: @active_channel_id,
              messages: @messages,
              activeAgents: @active_agents,
              workingAgents: @working_agents
            }
          }
          socket={@socket}
        />
      </div>
    </div>

    <.live_component
      module={EyeInTheSkyWebWeb.Components.NewSessionModal}
      id="new-session-modal"
      show={@show_agent_drawer}
      toggle_event="toggle_agent_drawer"
      submit_event="create_agent"
      projects={@all_projects}
      current_project={nil}
    />
    """
  end

  # Private functions

  defp get_project_id(params) do
    case params["project_id"] do
      nil ->
        # Default project ID
        1

      project_id when is_binary(project_id) ->
        # Try to parse as integer, otherwise use default
        try do
          case Integer.parse(project_id) do
            {int, ""} -> int
            # Partial parse (e.g., "123abc"), use default
            {_int, _rest} -> 1
            # Not a number at all, use default
            :error -> 1
          end
        rescue
          # Any exception, use default
          _ -> 1
        end

      project_id when is_integer(project_id) ->
        # Already an integer
        project_id

      _project_id ->
        # Any other type, use default
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
    # No channels exist, create default #general
    session_id = get_session_id(socket)

    case Channels.create_default_channel(project_id, session_id) do
      {:ok, channel} ->
        # Reload channels
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
      parent_message: serialize_message(parent_message),
      replies: Enum.map(parent_message.thread_replies, &serialize_message/1)
    }
  end

  defp serialize_channels(channels) do
    Enum.map(channels, fn channel ->
      %{
        id: channel.id,
        name: channel.name,
        description: channel.description,
        channel_type: channel.channel_type
      }
    end)
  end

  defp serialize_messages(messages) do
    Enum.map(messages, &serialize_message/1)
  end

  defp serialize_message(message) do
    session_name =
      if Ecto.assoc_loaded?(message.session) && message.session do
        message.session.name
      else
        nil
      end

    %{
      id: message.id,
      session_id: message.session_id,
      session_name: session_name,
      sender_role: message.sender_role,
      direction: message.direction,
      body: message.body,
      provider: message.provider,
      status: message.status,
      inserted_at: message.inserted_at,
      thread_reply_count: message.thread_reply_count || 0,
      reactions: serialize_reactions(message),
      metadata: message.metadata || %{}
    }
  end

  defp serialize_reactions(message) do
    if Ecto.assoc_loaded?(message.reactions) do
      message.reactions
      |> Enum.group_by(& &1.emoji)
      |> Enum.map(fn {emoji, reactions} ->
        %{
          emoji: emoji,
          count: length(reactions),
          session_ids: Enum.map(reactions, & &1.session_id)
        }
      end)
    else
      []
    end
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

  defp serialize_prompts(prompts) do
    Enum.map(prompts, fn prompt ->
      %{
        id: prompt.id,
        name: prompt.name,
        slug: prompt.slug,
        description: prompt.description,
        prompt_text: prompt.prompt_text
      }
    end)
  end
end
