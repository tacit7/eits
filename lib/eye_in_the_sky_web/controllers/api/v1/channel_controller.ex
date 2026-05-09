defmodule EyeInTheSkyWeb.Api.V1.ChannelController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Channels, Sessions}
  alias EyeInTheSky.Channels.Channel
  alias EyeInTheSky.Messaging.DMDelivery
  alias EyeInTheSky.Utils.ToolHelpers
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  POST /api/v1/channels - Create a new channel.
  Body:
    - name (required): channel name
    - project_id (optional): integer project ID; nil for global channels
    - channel_type (optional): "public" | "private", defaults to "public"
    - description (optional): human-readable description
    - session_id (optional): UUID or integer session ID of the creator
  """
  def create(conn, params) do
    name = String.trim(params["name"] || "")

    with :ok <- validate_name(name),
         {:ok, project_id} <- resolve_project_id(params["project_id"]),
         {:ok, creator_session_id} <- resolve_creator_session(params["session_id"]) do
      channel_type = params["channel_type"] || "public"
      channel_id = Channel.generate_id(project_id, name)

      attrs =
        %{
          id: channel_id,
          uuid: Ecto.UUID.generate(),
          name: name,
          channel_type: channel_type,
          project_id: project_id,
          created_by_session_id: if(creator_session_id, do: to_string(creator_session_id))
        }
        |> then(fn m ->
          case params["description"] do
            nil -> m
            desc -> Map.put(m, :description, desc)
          end
        end)

      case Channels.create_channel(attrs) do
        {:ok, channel} ->
          conn
          |> put_status(:created)
          |> json(%{
            success: true,
            message: "Channel created",
            channel: ApiPresenter.present_channel(channel)
          })

        {:error, %Ecto.Changeset{} = cs} ->
          {:error, cs}
      end
    end
  end

  @doc """
  GET /api/v1/channels/mine - List channels the current session is a member of.
  Query params: session_id (required) — UUID or integer session ID.
  """
  def mine(conn, params) do
    raw = params["session_id"] || ""

    with true <- raw != "",
         {:ok, int_id} <- ToolHelpers.resolve_session_int_id(raw) do
      channels = Channels.list_channels_for_session(int_id)

      json(conn, %{
        success: true,
        message: "#{length(channels)} channel(s) found",
        channels:
          Enum.map(channels, fn c ->
            %{
              id: c.id,
              uuid: c.uuid,
              name: c.name,
              description: c.description,
              channel_type: c.channel_type,
              project_id: c.project_id,
              role: c.role,
              joined_at: if(c.joined_at, do: to_string(c.joined_at))
            }
          end)
      })
    else
      false -> {:error, :bad_request, "session_id is required"}
      _ -> {:error, :not_found, "Session not found"}
    end
  end

  @doc "GET /api/v1/channels - List available chat channels."
  def index(conn, params) do
    channels =
      if params["project_id"] do
        project_id = parse_int(params["project_id"])

        if project_id,
          do: Channels.list_channels_for_project(project_id),
          else: Channels.list_channels()
      else
        Channels.list_channels()
      end

    json(conn, %{
      success: true,
      message: "#{length(channels)} channel(s) found",
      channels: Enum.map(channels, &ApiPresenter.present_channel/1)
    })
  end

  @doc """
  POST /api/v1/channels/:channel_id/members - Add a session to a channel.
  Body: session_id (required), role (optional, default "member")
  """
  def join(conn, %{"channel_id" => channel_id} = params) do
    with {:ok, channel} <- get_channel_by_id(channel_id),
         {:ok, raw} <- validate_session_id_param(params["session_id"]),
         {:ok, int_id} <- ToolHelpers.resolve_session_int_id(raw),
         {:ok, session} <- Sessions.get_session(int_id),
         {:ok, agent_id} <- get_session_agent_id(session) do
      role = params["role"] || "member"

      case Channels.add_member(channel.id, agent_id, session.id, role) do
        {:ok, member} ->
          Task.start(fn ->
            DMDelivery.deliver_and_persist(
              session.id,
              nil,
              channel_orientation_message(channel)
            )
          end)

          conn
          |> put_status(:created)
          |> json(%{
            success: true,
            message: "Joined channel #{channel.name}",
            member: ApiPresenter.present_channel_member(member)
          })

        {:error, :duplicate} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{success: false, error: "Already a member of this channel"})

        {:error, %Ecto.Changeset{} = cs} ->
          {:error, cs}
      end
    else
      {:error, :channel_not_found} -> {:error, :not_found, "Channel not found"}
      {:error, :session_id_required} -> {:error, :bad_request, "session_id is required"}
      {:error, :no_agent} -> {:error, :unprocessable_entity, "Session has no registered agent"}
      {:error, _} -> {:error, :not_found, "Session not found"}
    end
  end

  @doc "DELETE /api/v1/channels/:channel_id/members/:session_id - Remove a session from a channel."
  def leave(conn, %{"channel_id" => channel_id, "session_id" => session_id_param}) do
    with {:ok, channel} <- get_channel_by_id(channel_id),
         {:ok, int_id} <- ToolHelpers.resolve_session_int_id(session_id_param) do
      Channels.remove_member(channel.id, int_id)
      json(conn, %{success: true, message: "Left channel #{channel.name}"})
    else
      {:error, :channel_not_found} -> {:error, :not_found, "Channel not found"}
      _ -> {:error, :not_found, "Session not found"}
    end
  end

  @doc "GET /api/v1/channels/:channel_id/members - List members of a channel."
  def list_members(conn, %{"channel_id" => channel_id}) do
    case Channels.get_channel(channel_id) do
      nil ->
        {:error, :not_found, "Channel not found"}

      channel ->
        members = Channels.list_members_with_sessions(channel.id)

        json(conn, %{
          success: true,
          channel_id: channel.id,
          members:
            Enum.map(members, fn m ->
              %{
                agent_uuid: m.agent_uuid,
                session_id: m.session_id,
                session_uuid: m.session_uuid,
                session_name: m.session_name,
                role: m.role,
                joined_at: if(m.joined_at, do: to_string(m.joined_at))
              }
            end)
        })
    end
  end

  defp channel_orientation_message(channel) do
    """
    You have joined channel **#{channel.name}** (ID: `#{channel.id}`).

    Your env var `EITS_CHANNEL_ID=#{channel.id}` is set for this session.

    Key commands:
    - `eits channels messages #{channel.id}` — fetch recent messages
    - `eits channels send #{channel.id} "<text>"` — post a message
    - `eits channels mine` — list channels you belong to

    Mention routing:
    - `@<session_id>` — direct reply to a specific session
    - `@all` — broadcast to all channel members
    - No mention — ambient message (no auto-routing)

    [NO_RESPONSE]
    """
  end

  defp get_channel_by_id(id) do
    case Channels.get_channel(id) do
      nil -> {:error, :channel_not_found}
      channel -> {:ok, channel}
    end
  end

  defp validate_session_id_param(nil), do: {:error, :session_id_required}
  defp validate_session_id_param(""), do: {:error, :session_id_required}
  defp validate_session_id_param(raw), do: {:ok, raw}

  defp get_session_agent_id(session) do
    case session.agent_id do
      nil -> {:error, :no_agent}
      agent_id -> {:ok, agent_id}
    end
  end

  defp validate_name(""), do: {:error, :bad_request, "name is required"}
  defp validate_name(_), do: :ok

  defp resolve_project_id(nil), do: {:ok, nil}

  defp resolve_project_id(raw) do
    case parse_int(raw) do
      nil -> {:error, :bad_request, "project_id must be an integer"}
      id -> {:ok, id}
    end
  end

  defp resolve_creator_session(nil), do: {:ok, nil}

  defp resolve_creator_session(raw) do
    case ToolHelpers.resolve_session_int_id(raw) do
      {:ok, int_id} -> {:ok, int_id}
      _ -> {:error, :not_found, "session_id not found"}
    end
  end
end
