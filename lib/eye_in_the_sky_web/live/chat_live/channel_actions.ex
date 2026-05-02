defmodule EyeInTheSkyWeb.ChatLive.ChannelActions do
  @moduledoc """
  Handles channel membership events delegated from ChatLive.

  Keeps add/remove member and channel creation logic out of the main LiveView.
  """

  require Logger

  alias EyeInTheSky.{Channels, Sessions}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSkyWeb.ControllerHelpers
  alias EyeInTheSkyWeb.Helpers.AgentCreationHelpers
  import Phoenix.LiveView, only: [put_flash: 3, push_patch: 2]
  import EyeInTheSkyWeb.Helpers.UploadHelpers

  @spec handle_add_agent(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_add_agent(socket, %{"session_id" => session_id_str}) do
    channel_id = socket.assigns.active_channel_id

    with session_id when not is_nil(session_id) <- ControllerHelpers.parse_int(session_id_str),
         {:ok, session} <- Sessions.get_session(session_id) do
      agent_id = session.agent_id

      case Channels.add_member(channel_id, agent_id, session_id) do
        {:ok, _member} ->
          broadcast_system_event(
            channel_id,
            "Agent @#{session_id} (#{session.name || "unnamed"}) joined the channel"
          )

          Logger.info("Added agent session=#{session_id} to channel=#{channel_id}")
          {:noreply, refresh_members_and_picker(socket)}

        {:error, changeset} ->
          Logger.warning("Failed to add member: #{inspect(changeset)}")
          {:noreply, put_flash(socket, :error, "Agent already in channel or invalid")}
      end
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Invalid session ID format")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Session not found")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add agent to channel")}
    end
  end

  @spec handle_remove_agent(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_remove_agent(socket, %{"session_id" => session_id_str}) do
    channel_id = socket.assigns.active_channel_id

    with session_id when not is_nil(session_id) <- ControllerHelpers.parse_int(session_id_str),
         {:ok, session} <- Sessions.get_session(session_id) do
      Channels.remove_member(channel_id, session_id)

      broadcast_system_event(
        channel_id,
        "Agent @#{session_id} (#{session.name || "unnamed"}) left the channel"
      )

      Logger.info("Removed agent session=#{session_id} from channel=#{channel_id}")
      {:noreply, refresh_members_and_picker(socket)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Invalid session ID format")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Session not found")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove agent from channel")}
    end
  end

  @spec handle_create_channel(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_create_channel(socket, params) do
    name = (params["name"] || socket.assigns[:new_channel_name] || "") |> String.trim()

    if name == "" do
      {:noreply, Phoenix.Component.assign(socket, :new_channel_name, nil)}
    else
      project_id = socket.assigns[:project_id] || 1
      channel_id = EyeInTheSky.Channels.Channel.generate_id(project_id, name)

      case Channels.create_channel(%{
             id: channel_id,
             uuid: Ecto.UUID.generate(),
             name: name,
             channel_type: "public",
             project_id: project_id
           }) do
        {:ok, _channel} ->
          channels = EyeInTheSky.Channels.list_channels_for_project(project_id)

          {:noreply,
           socket
           |> Phoenix.Component.assign(:channels, EyeInTheSkyWeb.ChatPresenter.serialize_channels(channels))
           |> Phoenix.Component.assign(:new_channel_name, nil)
           |> push_patch(to: "/chat?channel_id=#{channel_id}")}

        {:error, _changeset} ->
          {:noreply, Phoenix.Component.assign(socket, :new_channel_name, nil)}
      end
    end
  end

  @spec handle_create_agent(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_create_agent(socket, params) do
    channel_id = socket.assigns.active_channel_id
    agent_name = params["agent_name"] || ""

    agent_description =
      if agent_name != "", do: agent_name, else: "Channel agent for #{channel_id}"

    {:ok, _creating_msg} =
      EyeInTheSky.ChannelMessages.send_channel_message(%{
        channel_id: channel_id,
        session_id: nil,
        sender_role: "system",
        recipient_role: "agent",
        provider: "system",
        body:
          "Creating new agent (#{params["model"] || "sonnet"})#{if agent_name != "", do: " - #{agent_name}", else: ""}..."
      })

    description = params["description"] || ""
    base_instructions = if description != "", do: description, else: agent_description
    uploaded_images = consume_agent_images(socket)
    instructions = append_image_paths(base_instructions, uploaded_images)

    project_path =
      case Enum.find(socket.assigns.all_projects, fn p ->
             to_string(p.id) == to_string(params["project_id"])
           end) do
        nil -> nil
        project -> project.path
      end

    if is_nil(project_path) do
      {:noreply, put_flash(socket, :error, "No project path configured for this agent")}
    else
      opts =
        AgentCreationHelpers.build_opts(params,
          project_path: project_path,
          description: agent_description,
          instructions: instructions
        )

      case AgentManager.create_agent(opts) do
        {:ok, %{agent: agent, session: session}} ->
          join_agent_to_channel(channel_id, agent, session, agent_description)

          {:noreply,
           socket
           |> Phoenix.Component.assign(:show_agent_drawer, false)
           |> refresh_members_and_picker()}

        {:error, reason} ->
          {:noreply,
           socket
           |> Phoenix.Component.assign(:show_agent_drawer, false)
           |> put_flash(:error, "Failed to create agent: #{inspect(reason)}")}
      end
    end
  end

  # Private

  defp refresh_members_and_picker(socket) do
    channel_id = socket.assigns.active_channel_id
    channel_members = EyeInTheSkyWeb.ChatLive.ChannelHelpers.load_channel_members(channel_id)
    search = socket.assigns[:session_search] || ""

    sessions_by_project =
      EyeInTheSkyWeb.ChatLive.ChannelHelpers.build_sessions_by_project(
        channel_members,
        socket.assigns.all_projects,
        search
      )

    socket
    |> Phoenix.Component.assign(:channel_members, channel_members)
    |> Phoenix.Component.assign(:sessions_by_project, sessions_by_project)
  end

  defp join_agent_to_channel(nil, _agent, _session, _description), do: :ok

  defp join_agent_to_channel(channel_id, agent, session, description) do
    case Channels.add_member(channel_id, agent.id, session.id) do
      {:ok, _} ->
        broadcast_system_event(
          channel_id,
          "Agent @#{session.id} (#{description}) joined the channel"
        )

      {:error, _} ->
        :ok
    end
  end

  defp broadcast_system_event(channel_id, body) do
    EyeInTheSky.ChannelMessages.send_channel_message(%{
      channel_id: channel_id,
      session_id: nil,
      sender_role: "system",
      recipient_role: "agent",
      provider: "system",
      body: body
    })
  end
end
