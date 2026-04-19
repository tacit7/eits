defmodule EyeInTheSkyWeb.Api.V1.MessagingController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  require Logger
  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, ChannelMessages, Channels, Messages, Sessions}
  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Utils.ToolHelpers
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
        {:error, :bad_request, "from_session_id is required"}

      is_nil(to_raw) or to_raw == "" ->
        {:error, :bad_request, "to_session_id is required"}

      is_nil(params["message"]) or params["message"] == "" ->
        {:error, :bad_request, "message is required"}

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
        {:ok, session} -> {:ok, session}
        {:error, :not_found} -> resolve_session_from_agent_uuid(raw)
      end
    end
  end

  defp resolve_session_from_agent_uuid(raw) do
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

  defp resolve_to_session(raw) do
    if int_id = ToolHelpers.parse_int(raw),
      do: Sessions.get_session(int_id),
      else: Sessions.get_session_by_uuid(raw)
  end

  @terminated_statuses ~w(completed failed)

  defp do_dm(conn, params, from_raw, to_raw) do
    with {:from, {:ok, from_session}} <- {:from, resolve_from_session(from_raw)},
         {:from_active, false} <-
           {:from_active, from_session.status in @terminated_statuses},
         {:to, {:ok, to_session}} <- {:to, resolve_to_session(to_raw)} do
      response_required = params["response_required"] in [true, "true", "1", 1]
      sender_name = ApiPresenter.resolve_session_sender_name(from_session)

      dm_body =
        "DM from:#{sender_name} (session:#{from_session.uuid}) #{trim_param(params["message"])}"

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
          persist_dm(conn, to_session, attrs)

        {:error, reason} ->
          Logger.error("DM routing failed for session #{to_session.id}: #{inspect(reason)}")
          {:error, :internal_server_error, "Failed to deliver message"}
      end
    else
      {:from, {:error, :not_found}} ->
        {:error, :not_found, "Sender session not found"}

      {:from_active, true} ->
        {:error, :unprocessable_entity, "Sender session is terminated and cannot send DMs"}

      {:to, {:error, :not_found}} ->
        {:error, :not_found, "Target session not found"}
    end
  end

  @doc """
  POST /api/v1/channels - Create a new channel.
  Body:
    - name (required): channel name
    - project_id (optional): integer project ID; nil for global channels
    - channel_type (optional): "public" | "private", defaults to "public"
    - description (optional): human-readable description
    - session_id (optional): UUID or integer session ID of the creator
  """
  def create_channel(conn, params) do
    name = String.trim(params["name"] || "")

    with :ok <- validate_name(name),
         {:ok, project_id} <- resolve_project_id(params["project_id"]),
         {:ok, creator_session_id} <- resolve_creator_session(params["session_id"]) do
      channel_type = params["channel_type"] || "public"
      channel_id = EyeInTheSky.Channels.Channel.generate_id(project_id, name)

      attrs =
        %{
          id: channel_id,
          uuid: Ecto.UUID.generate(),
          name: name,
          channel_type: channel_type,
          project_id: project_id,
          # created_by_session_id is a :string field in the schema
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

        # Let FallbackController render via its {:error, %Ecto.Changeset{}} clause
        {:error, %Ecto.Changeset{} = cs} ->
          {:error, cs}
      end
    end
  end

  defp validate_name(""), do: {:error, :bad_request, "name is required"}
  defp validate_name(_), do: :ok

  # nil → ok (global channel); non-nil but non-integer → 400
  defp resolve_project_id(nil), do: {:ok, nil}

  defp resolve_project_id(raw) do
    case parse_int(raw) do
      nil -> {:error, :bad_request, "project_id must be an integer"}
      id -> {:ok, id}
    end
  end

  # nil → ok (no creator); provided but unresolvable → 404
  defp resolve_creator_session(nil), do: {:ok, nil}

  defp resolve_creator_session(raw) do
    case ToolHelpers.resolve_session_int_id(raw) do
      {:ok, int_id} -> {:ok, int_id}
      _ -> {:error, :not_found, "session_id not found"}
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
        {:error, :bad_request, "session_id is required"}

      is_nil(params["body"]) or params["body"] == "" ->
        {:error, :bad_request, "body is required"}

      true ->
        case ToolHelpers.resolve_session_int_id(params["session_id"]) do
          {:ok, int_id} -> do_send_channel_message(conn, channel_id, int_id, params)
          {:error, reason} -> {:error, :not_found, reason}
        end
    end
  end

  defp do_send_channel_message(conn, channel_id, int_id, params) do
    attrs = %{
      channel_id: channel_id,
      session_id: int_id,
      body: trim_param(params["body"]),
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

      {:error, _cs} ->
        {:error, "Failed to send message"}
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

  defp persist_dm(conn, to_session, attrs) do
    case Messages.find_recent_dm(to_session.id, attrs.body, seconds: 30) do
      nil ->
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

          {:error, _cs} ->
            {:error, "Failed to persist DM"}
        end

      existing ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          message: "DM delivered to session #{to_session.id}",
          message_id: to_string(existing.id),
          message_uuid: existing.uuid
        })
    end
  end

  defp agent_manager_mod do
    Application.get_env(:eye_in_the_sky, :agent_manager_module, AgentManager)
  end

  # Resolve a readable name from the sender session.
  # Priority: team member name > session name > agent description > "agent"
end
