defmodule EyeInTheSkyWebWeb.Api.V1.MessagingController do
  use EyeInTheSkyWebWeb, :controller

  action_fallback EyeInTheSkyWebWeb.Api.V1.FallbackController

  require Logger
  import EyeInTheSkyWebWeb.ControllerHelpers

  alias EyeInTheSkyWeb.{Agents, Channels, Messages, Sessions}
  alias EyeInTheSkyWeb.Claude.AgentManager

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
        with {:sender, {:ok, _agent}} <- {:sender, Agents.get_agent_by_uuid(params["sender_id"])},
             {:session, {:ok, session}} <- {:session, Sessions.get_session_by_uuid(target_uuid)} do
          response_required = params["response_required"] in [true, "true", "1", 1]

          attrs = %{
            uuid: Ecto.UUID.generate(),
            session_id: session.id,
            body: params["message"],
            sender_role: "agent",
            recipient_role: "agent",
            direction: "inbound",
            status: "sent",
            provider: "claude",
            metadata: %{
              sender_id: params["sender_id"],
              response_required: response_required
            }
          }

          case agent_manager_mod().send_message(session.id, params["message"]) do
            result when result == :ok or (is_tuple(result) and elem(result, 0) == :ok) ->
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
                  |> json(%{error: "Failed to persist DM", details: translate_errors(cs)})
              end

            {:error, reason} ->
              Logger.error(
                "DM routing failed for session #{session.id}: #{inspect(reason)}"
              )

              conn
              |> put_status(:internal_server_error)
              |> json(%{error: "Failed to route message to agent", reason: inspect(reason)})
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

  defp agent_manager_mod do
    Application.get_env(:eye_in_the_sky_web, :agent_manager_module, AgentManager)
  end
end
