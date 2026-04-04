defmodule EyeInTheSkyWeb.Api.V1.MessagingController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  require Logger
  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, ChannelMessages, Channels, Messages, Sessions}
  alias EyeInTheSky.Utils.ToolHelpers
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  POST /api/v1/dm - Send a direct message to an agent session.
  Body:
    - from_session_id (required): integer session ID or UUID of the sending session
    - to_session_id (required): integer session ID or UUID of the target session
    - message (required): message body
    - response_required (optional): boolean, defaults to false

  Legacy params also accepted for backward compat:
    - sender_id: agent UUID (resolved to session via agent.id)
    - target_session_id: session UUID (alias for to_session_id)
  """
  # 30 DMs per sender per minute — prevents injection flooding into agent sessions
  @dm_rate_limit {30, :timer.minutes(1)}

  def dm(conn, params) do
    from_raw = params["from_session_id"] || params["sender_id"]
    to_raw = params["to_session_id"] || params["target_session_id"]

    cond do
      is_nil(from_raw) or from_raw == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "from_session_id is required"})

      is_nil(to_raw) or to_raw == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "to_session_id is required"})

      is_nil(params["message"]) or params["message"] == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "message is required"})

      true ->
        {limit, scale} = @dm_rate_limit
        key = "dm:#{from_raw}"

        case EyeInTheSky.RateLimiter.hit(key, scale, limit) do
          {:deny, _} ->
            conn |> put_status(429) |> json(%{error: "too many requests"})

          {:allow, _} ->
            do_dm(conn, params, from_raw, to_raw)
        end
    end
  end

  # Resolve a session from an integer ID, UUID, or agent UUID (legacy sender_id).
  defp resolve_from_session(raw) do
    if int_id = ToolHelpers.parse_int(raw) do
      Sessions.get_session(int_id)
    else
      # Try as session UUID first
      case Sessions.get_session_by_uuid(raw) do
        {:ok, session} ->
          {:ok, session}

        {:error, :not_found} ->
          # Fallback: treat as agent UUID (legacy sender_id)
          case Agents.get_agent_by_uuid(raw) do
            {:ok, agent} ->
              case Sessions.list_sessions_for_agent(agent.id, limit: 1) do
                [session | _] -> {:ok, session}
                _ -> {:error, :not_found}
              end

            _ ->
              {:error, :not_found}
          end
      end
    end
  end

  defp resolve_to_session(raw) do
    if int_id = ToolHelpers.parse_int(raw),
      do: Sessions.get_session(int_id),
      else: Sessions.get_session_by_uuid(raw)
  end

  defp do_dm(conn, params, from_raw, to_raw) do
    with {:from, {:ok, from_session}} <- {:from, resolve_from_session(from_raw)},
         {:to, {:ok, to_session}} <- {:to, resolve_to_session(to_raw)} do
      response_required = params["response_required"] in [true, "true", "1", 1]
      sender_name = ApiPresenter.resolve_session_sender_name(from_session)

      dm_body =
        "DM from:#{sender_name} (session:#{from_session.uuid}) #{params["message"]}"

      attrs = %{
        uuid: Ecto.UUID.generate(),
        session_id: to_session.id,
        from_session_id: from_session.id,
        to_session_id: to_session.id,
        body: dm_body,
        sender_role: "agent",
        recipient_role: "agent",
        direction: "inbound",
        status: "sent",
        provider: "claude",
        metadata: %{
          sender_name: sender_name,
          from_session_uuid: from_session.uuid,
          to_session_uuid: to_session.uuid,
          response_required: response_required
        }
      }

      case agent_manager_mod().send_message(to_session.id, dm_body) do
        result when result == :ok or (is_tuple(result) and elem(result, 0) == :ok) ->
          case Messages.create_message(attrs) do
            {:ok, msg} ->
              EyeInTheSky.Events.session_new_dm(to_session.id, msg)

              conn
              |> put_status(:created)
              |> json(%{
                success: true,
                message: "DM delivered to session #{to_session.id}",
                message_id: to_string(msg.id),
                message_uuid: msg.uuid
              })

            {:error, cs} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Failed to persist DM", details: translate_errors(cs)})
          end

        {:error, reason} ->
          Logger.error("DM routing failed for session #{to_session.id}: #{inspect(reason)}")

          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to route message to agent", reason: inspect(reason)})
      end
    else
      {:from, {:error, :not_found}} ->
        conn |> put_status(:not_found) |> json(%{error: "Sender session not found"})

      {:to, {:error, :not_found}} ->
        conn |> put_status(:not_found) |> json(%{error: "Target session not found"})
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
      channels: Enum.map(channels, &ApiPresenter.present_channel/1)
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
        case ToolHelpers.resolve_session_int_id(params["session_id"]) do
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

            case ChannelMessages.create_channel_message(attrs) do
              {:ok, msg} ->
                EyeInTheSky.Events.channel_message(channel_id, msg)

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

  @doc """
  GET /api/v1/channels/:channel_id/messages - List recent messages for a channel.
  Query params: limit (optional, default 20, max 200)
  """
  def list_channel_messages(conn, %{"channel_id" => channel_id} = params) do
    limit =
      case parse_int(params["limit"], 20) do
        n when n > 0 and n <= 200 -> n
        _ -> 20
      end

    messages = ChannelMessages.list_messages_for_channel(channel_id, limit: limit)

    json(conn, %{
      success: true,
      channel_id: channel_id,
      count: length(messages),
      messages: Enum.map(messages, &ApiPresenter.present_channel_message/1)
    })
  end

  defp agent_manager_mod do
    Application.get_env(:eye_in_the_sky, :agent_manager_module, AgentManager)
  end

  # Resolve a readable name from the sender session.
  # Priority: team member name > session name > agent description > "agent"
end
