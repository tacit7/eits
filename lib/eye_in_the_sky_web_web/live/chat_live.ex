defmodule EyeInTheSkyWebWeb.ChatLive do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.{Agents, Channels, Messages, Prompts, Sessions}

  # Deterministic UUIDs for the web UI user
  @web_agent_uuid "00000000-0000-0000-0000-000000000001"
  @web_session_uuid "00000000-0000-0000-0000-000000000002"

  @impl true
  def mount(_params, _session, socket) do
    session_id = ensure_web_session()

    {:ok,
     socket
     |> assign(:session_id, session_id)
     |> assign(:working_sessions, %{})
     |> assign(:subscribed_sessions, MapSet.new())}
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
            {:ok, a} -> a
            {:error, :not_found} ->
              {:ok, a} = Agents.create_agent(%{
                uuid: @web_agent_uuid,
                description: "Web UI User",
                source: "web"
              })
              a
          end

        {:ok, session} = Sessions.create_session(%{
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

    # Load active sessions for @ autocomplete (exclude web UI session)
    active_agents =
      Sessions.list_active_sessions()
      |> Enum.reject(&(&1.uuid == @web_session_uuid))
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

    socket =
      socket
      |> assign(:page_title, "Chat")
      |> assign(:project_id, project_id)
      |> assign(:channels, serialize_channels(channels))
      |> assign(:active_channel_id, channel_id)
      |> assign(:messages, messages)
      |> assign(:unread_counts, unread_counts)
      |> assign(:active_thread, active_thread)
      |> assign(:agent_status_counts, agent_status_counts)
      |> assign(:prompts, prompts)
      |> assign(:active_agents, active_agents)

    {:noreply, socket}
  end

  @impl true
  def handle_event("change_channel", %{"channel_id" => channel_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?channel_id=#{channel_id}")}
  end

  @impl true
  def handle_event(
        "send_direct_message",
        %{"session_id" => target_session_id, "body" => body, "channel_id" => channel_id},
        socket
      ) do
    user_session_id = get_session_id(socket)

    # Parse target_session_id to integer if it's a string
    target_id =
      case target_session_id do
        id when is_integer(id) -> id
        id when is_binary(id) ->
          case Integer.parse(id) do
            {int, ""} -> int
            _ -> nil
          end
        _ -> nil
      end

    if is_nil(target_id) do
      {:noreply, put_flash(socket, :error, "Invalid session ID")}
    else
      # Create message in channel (with user's session_id as sender)
      case Messages.send_channel_message(%{
             channel_id: channel_id,
             session_id: user_session_id,
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

          # Continue the target agent's Claude session with the message
          with {:ok, session} <- Sessions.get_session(target_id),
               {:ok, agent} <- Agents.get_agent(session.agent_id) do
            project_path = agent.git_worktree_path || File.cwd!()

            # Get latest NATS sequence for channel context
            latest_seq = EyeInTheSkyWeb.NATS.Reader.get_latest_sequence(channel_id)
            start_from = max(0, latest_seq - 10)

            prompt_with_reminder = """
            REMINDER: Use i-chat-send MCP tool to send your response to the channel.

            Channel context available via NATS:
            - Channel ID: #{channel_id}
            - Latest NATS sequence: #{latest_seq}
            - Replay from sequence: #{start_from} (last 10 messages)

            To see recent channel history, use:
            i-nats-listen with session_id="#{session.uuid}" and last_sequence=#{start_from}

            New message: #{body}
            """

            case EyeInTheSkyWeb.Claude.SessionManager.resume_session(
                   session.uuid,
                   prompt_with_reminder,
                   model: "sonnet",
                   project_path: project_path
                 ) do
              {:ok, _session_ref} ->
                socket = subscribe_session_status(socket, session.uuid, target_id)
                {:noreply, socket}

              {:error, reason} ->
                {:noreply, put_flash(socket, :error, "Failed to send to agent: #{inspect(reason)}")}
            end
          else
            {:error, :not_found} ->
              {:noreply, put_flash(socket, :error, "Agent session not found")}
          end

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    end
  end


  @impl true
  def handle_event("send_channel_message", %{"channel_id" => channel_id, "body" => body}, socket) do
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
        # Also append to JSONL file (opcode-style)
        if session_id && socket.assigns.project_id do
          project_id_str = get_project_id_for_jsonl(socket)

          Messages.append_to_jsonl(project_id_str, session_id, %{
            id: message.id,
            session_id: session_id,
            sender_role: "user",
            recipient_role: "agent",
            provider: "claude",
            body: body,
            direction: "outbound",
            inserted_at: DateTime.to_iso8601(message.inserted_at)
          })
        end

        # Broadcast to channel subscribers (including sender)
        Phoenix.PubSub.broadcast(
          EyeInTheSkyWeb.PubSub,
          "channel:#{channel_id}:messages",
          {:new_message, message}
        )

        # Publish to NATS for agents to receive
        EyeInTheSkyWeb.NATS.Publisher.publish_channel_message(message, channel_id)

        # Mark channel as read
        Channels.mark_as_read(channel_id, session_id)

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to send message")}
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

        # Publish to NATS
        EyeInTheSkyWeb.NATS.Publisher.publish_channel_message(message, channel_id)

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
  def handle_event("create_channel", _params, socket) do
    # TODO: Open modal or navigate to channel creation page
    {:noreply, put_flash(socket, :info, "Channel creation coming soon")}
  end

  @impl true
  def handle_event("create_agent", params, socket) do
    %{
      "agent_type" => agent_type,
      "model" => model,
      "instructions" => instructions,
      "channel_id" => channel_id
    } = params

    prompt_id = params["prompt_id"]
    description = params["description"]
    project_id = socket.assigns.project_id

    # Log what we received
    require Logger
    Logger.info("📝 Creating agent with instructions: #{inspect(instructions)}")
    Logger.info("🎯 Prompt ID: #{inspect(prompt_id)}")
    Logger.info("📛 Description: #{inspect(description)}")

    # Generate UUIDs for new agent
    agent_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()

    # Fetch prompt if provided
    prompt_name =
      if prompt_id do
        try do
          prompt = Prompts.get_prompt!(prompt_id)
          prompt.name
        rescue
          Ecto.NoResultsError -> nil
        end
      else
        nil
      end

    # Use description or fallback to generic text
    agent_description =
      if description && description != "" do
        description
      else
        "Channel agent for #{channel_id}"
      end

    session_name =
      if description && description != "" do
        description
      else
        "Channel session"
      end

    # Send immediate "creating agent" message
    {:ok, creating_msg} =
      Messages.send_channel_message(%{
        channel_id: channel_id,
        session_id: nil,
        sender_role: "system",
        recipient_role: "agent",
        provider: "system",
        body:
          "🤖 Creating new #{agent_type} agent (#{model})#{if description && description != "", do: " - #{description}", else: ""}..."
      })

    # Publish to NATS
    EyeInTheSkyWeb.NATS.Publisher.publish_channel_message(creating_msg, channel_id)

    # Spawn agent creation in background
    spawn(fn ->
      # Create agent record in database
      {:ok, agent} =
        Agents.create_agent(%{
          uuid: agent_id,
          agent_type: agent_type,
          project_id: project_id,
          status: "active",
          description: agent_description
        })

      # Create session record
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      {:ok, new_session} =
        EyeInTheSkyWeb.Sessions.create_session(%{
          uuid: session_id,
          agent_id: agent.id,
          name: session_name,
          description: "session-id #{session_id} agent-id #{agent_id}",
          started_at: now
        })

      session_int_id = new_session.id

      # Get project path (default to current directory if not set)
      project_path = File.cwd!()

      # Spawn Claude with proper flags
      case EyeInTheSkyWeb.Claude.CLI.spawn_channel_agent(
             session_id,
             agent_id,
             instructions,
             model: model,
             project_path: project_path,
             channel_id: channel_id,
             prompt_name: prompt_name
           ) do
        {:ok, _port, _session_ref} ->
          # Success - Claude will start responding
          {:ok, intro_msg} =
            Messages.send_channel_message(%{
              channel_id: channel_id,
              session_id: session_int_id,
              sender_role: "agent",
              recipient_role: "user",
              provider: agent_type,
              body: "Hello! I'm a #{agent_type} agent running #{model}. Ready to help!"
            })

          EyeInTheSkyWeb.NATS.Publisher.publish_channel_message(intro_msg, channel_id)

        {:error, reason} ->
          # Failed to spawn
          {:ok, error_msg} =
            Messages.send_channel_message(%{
              channel_id: channel_id,
              session_id: nil,
              sender_role: "system",
              recipient_role: "user",
              provider: "system",
              body: "❌ Failed to create agent: #{inspect(reason)}"
            })

          EyeInTheSkyWeb.NATS.Publisher.publish_channel_message(error_msg, channel_id)
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, _message}, socket) do
    require Logger
    Logger.info("📨 Received new_message broadcast for channel #{socket.assigns.active_channel_id}")

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
  def handle_info({:session_status, session_uuid, status}, socket) do
    working =
      case status do
        :working ->
          socket.assigns.working_sessions

        s when s in [:idle, :error, :queue_full] ->
          Map.delete(socket.assigns.working_sessions, session_uuid)

        _ ->
          socket.assigns.working_sessions
      end

    {:noreply, assign(socket, :working_sessions, working)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />
    <div style="position: fixed; top: 0; left: 0; right: 0; bottom: 0; overflow: hidden;">
      <.svelte
        name="AgentMessagesPanel"
        props={
          %{
            channels: @channels,
            activeChannelId: @active_channel_id,
            messages: @messages,
            unreadCounts: @unread_counts,
            activeThread: @active_thread,
            agentStatusCounts: @agent_status_counts,
            prompts: @prompts,
            activeAgents: @active_agents,
            workingSessions: Map.values(@working_sessions)
          }
        }
        socket={@socket}
      />
    </div>
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

  defp get_project_id_for_jsonl(socket) do
    # For JSONL storage, use channel_id as the project identifier
    # (Claude Code uses path-based project IDs, not database IDs)
    socket.assigns.active_channel_id || "default"
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

  defp subscribe_session_status(socket, session_uuid, session_int_id) do
    socket =
      if connected?(socket) && !MapSet.member?(socket.assigns.subscribed_sessions, session_uuid) do
        Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "session:#{session_uuid}:status")

        assign(
          socket,
          :subscribed_sessions,
          MapSet.put(socket.assigns.subscribed_sessions, session_uuid)
        )
      else
        socket
      end

    assign(socket, :working_sessions, Map.put(socket.assigns.working_sessions, session_uuid, session_int_id))
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
      reactions: serialize_reactions(message)
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
