defmodule EyeInTheSkyWebWeb.Api.V1.MessagingController do
  use EyeInTheSkyWebWeb, :controller

  action_fallback EyeInTheSkyWebWeb.Api.V1.FallbackController

  import EyeInTheSkyWebWeb.ControllerHelpers

  import Ecto.Query, only: [from: 2]

  alias EyeInTheSkyWeb.{Agents, Channels, Messages, Repo, Sessions, Teams}

  @doc """
  POST /api/v1/dm - Send a direct message to an agent session.
  Body:
    - sender_id (required): UUID of the sending agent — must exist in the agents table
    - target_session_id (required): UUID of the target session
    - message (required): message body
    - response_required (optional): boolean, defaults to false
  """
  def dm(conn, params) do
    target_uuid = params["target_session_id"]

    cond do
      is_nil(params["sender_id"]) or params["sender_id"] == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "sender_id is required"})

      is_nil(target_uuid) or target_uuid == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "target_session_id is required"})

      is_nil(params["message"]) or params["message"] == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "message is required"})

      true ->
        with {:sender, {:ok, agent}} <- {:sender, Agents.get_agent_by_uuid(params["sender_id"])},
             {:session, {:ok, session}} <- {:session, Sessions.get_session_by_uuid(target_uuid)} do
          response_required = params["response_required"] in [true, "true", "1", 1]
          sender_name = resolve_sender_name(agent)

          attrs = %{
            uuid: Ecto.UUID.generate(),
            session_id: session.id,
            body: "DM from:#{sender_name} #{params["message"]}",
            sender_role: "agent",
            recipient_role: "agent",
            direction: "inbound",
            status: "sent",
            provider: "claude",
            metadata: %{
              sender_id: params["sender_id"],
              sender_name: sender_name,
              response_required: response_required
            }
          }

          case Messages.create_message(attrs) do
            {:ok, msg} ->
              Phoenix.PubSub.broadcast(
                EyeInTheSkyWeb.PubSub,
                "session:#{session.id}",
                {:new_dm, msg}
              )

              conn
              |> put_status(:created)
              |> json(%{
                success: true,
                message: "DM delivered to session #{session.id}",
                message_id: to_string(msg.id),
                message_uuid: msg.uuid
              })

            {:error, cs} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to deliver DM", details: translate_errors(cs)})
          end
        else
          {:sender, {:error, :not_found}} ->
            conn |> put_status(:not_found) |> json(%{error: "Sender agent not found"})

          {:session, {:error, :not_found}} ->
            conn |> put_status(:not_found) |> json(%{error: "Target session not found"})
        end
    end
  end

  @doc """
  GET /api/v1/channels - List available chat channels.
  Query params: project_id (optional)
  """
  def list_channels(conn, params) do
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
      channels:
        Enum.map(channels, fn ch ->
          %{
            id: to_string(ch.id),
            name: ch.name,
            description: ch.description,
            channel_type: ch.channel_type,
            project_id: ch.project_id
          }
        end)
    })
  end

  @doc """
  POST /api/v1/channels/:channel_id/messages - Send a message to a channel.
  Body: session_id, body, sender_role (optional), recipient_role (optional)
  """
  def send_channel_message(conn, %{"channel_id" => channel_id} = params) do
    cond do
      is_nil(params["session_id"]) or params["session_id"] == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "session_id is required"})

      is_nil(params["body"]) or params["body"] == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "body is required"})

      true ->
        case resolve_session_id(params["session_id"]) do
          {:ok, int_id} ->
            attrs = %{
              channel_id: channel_id,
              session_id: int_id,
              body: params["body"],
              sender_role: params["sender_role"] || "agent",
              recipient_role: params["recipient_role"] || "user",
              provider: params["provider"] || "claude",
              direction: "outbound",
              status: "sent"
            }

            case Messages.create_channel_message(attrs) do
              {:ok, msg} ->
                Phoenix.PubSub.broadcast(
                  EyeInTheSkyWeb.PubSub,
                  "channel:#{channel_id}:messages",
                  {:new_message, msg}
                )

                conn
                |> put_status(:created)
                |> json(%{success: true, message: "Message sent", message_id: to_string(msg.id)})

              {:error, cs} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Failed to send message", details: translate_errors(cs)})
            end

          {:error, reason} ->
            conn |> put_status(:not_found) |> json(%{error: reason})
        end
    end
  end

  defp resolve_session_id(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {int_id, ""} ->
        {:ok, int_id}

      _ ->
        case Sessions.get_session_by_uuid(raw) do
          {:ok, session} -> {:ok, session.id}
          {:error, :not_found} -> {:error, "Session not found: #{raw}"}
        end
    end
  end

  # Resolve a readable name for the sender agent.
  # Priority: team member name > session name > agent description > "agent"
  defp resolve_sender_name(agent) do
    case Teams.get_member_by_agent_id(agent.id) do
      %{name: name} when is_binary(name) and name != "" ->
        name

      _ ->
        # Fall back to the agent's latest session name or description
        case Repo.one(
               from s in EyeInTheSkyWeb.Sessions.Session,
                 where: s.agent_id == ^agent.id,
                 where: not is_nil(s.name) and s.name != "",
                 order_by: [desc: s.id],
                 limit: 1,
                 select: s.name
             ) do
          name when is_binary(name) -> name
          _ -> agent.description || agent.project_name || "agent"
        end
    end
  end

end
