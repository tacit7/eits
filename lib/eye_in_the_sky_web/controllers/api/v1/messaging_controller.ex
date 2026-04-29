defmodule EyeInTheSkyWeb.Api.V1.MessagingController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  require Logger
  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, AsyncTask, ChannelMessages, Channels, Messages, Sessions, Teams}
  alias EyeInTheSky.Messaging.DMDelivery
  alias EyeInTheSky.Utils.ToolHelpers
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/dm - List inbound DMs for a session.
  Query params:
    - session (required): integer session ID or UUID
    - limit (optional): max messages to return, default 20
  """
  def list_dms(conn, params) do
    session_raw = params["session"] || params["session_id"]
    from_raw = params["from"] || params["from_session_id"]
    limit = min(String.to_integer(params["limit"] || "20"), 100)

    if is_nil(session_raw) or session_raw == "" do
      {:error, :bad_request, "session is required"}
    else
      with {:ok, session} <- Sessions.resolve(session_raw),
           {:ok, from_id} <- resolve_optional_session_id(from_raw) do
        messages = Messages.list_inbound_dms(session.id, limit, from_session_id: from_id)

        json(conn, %{
          session_id: session.id,
          session_uuid: session.uuid,
          count: length(messages),
          filter_from: from_raw,
          messages:
            Enum.map(messages, fn msg ->
              %{
                id: msg.id,
                uuid: msg.uuid,
                body: msg.body,
                from_session_id: msg.from_session_id,
                to_session_id: msg.to_session_id,
                inserted_at: msg.inserted_at
              }
            end)
        })
      else
        {:error, :not_found} -> {:error, :not_found, "session not found"}
        {:error, :bad_request, reason} -> {:error, :bad_request, reason}
      end
    end
  end

  # Resolves an optional session identifier to its integer ID.
  # Returns {:ok, nil} when raw is nil/empty (no filter).
  defp resolve_optional_session_id(nil), do: {:ok, nil}
  defp resolve_optional_session_id(""), do: {:ok, nil}

  defp resolve_optional_session_id(raw) do
    case Sessions.resolve(raw) do
      {:ok, session} -> {:ok, session.id}
      {:error, :not_found} -> {:error, :not_found, "from session not found: #{raw}"}
    end
  end

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

  # Resolves a session from a raw value. :from also falls back to agent UUID lookup (legacy sender_id).
  defp resolve_session_target(%{raw: raw, kind: :from}) do
    if int_id = ToolHelpers.parse_int(raw) do
      Sessions.get_session(int_id)
    else
      case Sessions.get_session_by_uuid(raw) do
        {:ok, session} ->
          {:ok, session}

        {:error, :not_found} ->
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

  defp resolve_session_target(%{raw: raw, kind: :to}) do
    if int_id = ToolHelpers.parse_int(raw),
      do: Sessions.get_session(int_id),
      else: Sessions.get_session_by_uuid(raw)
  end

  # Allowlist: only sessions actively processing or between turns can receive DMs.
  # Any status not in this list (waiting, completed, failed, archived, compacting, etc.) is non-receivable.
  @receivable_statuses ~w(working idle)

  defp do_dm(conn, params, from_raw, to_raw) do
    with {:from, {:ok, from_session}} <- {:from, resolve_session_target(%{raw: from_raw, kind: :from})},
         {:from_active, false} <-
           {:from_active, from_session.status in Sessions.terminated_statuses()},
         {:to, {:ok, to_session}} <- {:to, resolve_session_target(%{raw: to_raw, kind: :to})},
         {:to_receivable, true} <-
           {:to_receivable, to_session.status in @receivable_statuses} do
      response_required = params["response_required"] in [true, "true", "1", 1]
      sender_name = ApiPresenter.resolve_session_sender_name(from_session)

      dm_body =
        "DM from:#{sender_name} (session:#{from_session.uuid}) #{trim_param(params["message"])}"

      # Auto-constructed metadata context
      metadata = %{
        sender_name: sender_name,
        from_session_uuid: from_session.uuid,
        to_session_uuid: to_session.uuid,
        response_required: response_required
      }

      # Merge with optional request metadata (request metadata takes precedence)
      metadata =
        case params["metadata"] do
          nil -> metadata
          "" -> metadata
          req_metadata when is_map(req_metadata) -> Map.merge(metadata, req_metadata)
          _ -> metadata
        end

      case Messages.find_recent_dm(to_session.id, dm_body, seconds: 30) do
        nil ->
          case DMDelivery.deliver_and_persist(to_session.id, from_session.id, dm_body, metadata) do
            {:ok, msg} ->
              success_response(conn, to_session, msg)

            {:error, reason} ->
              Logger.error("DM routing failed for session #{to_session.id}: #{inspect(reason)}")
              {:error, :internal_server_error, "Failed to deliver message"}
          end

        existing ->
          success_response(conn, to_session, existing)
      end
    else
      {:from, {:error, :not_found}} ->
        {:error, :not_found, "Sender session not found"}

      {:from_active, true} ->
        {:error, :unprocessable_entity, "Sender session is terminated and cannot send DMs"}

      {:to, {:error, :not_found}} ->
        {:error, :not_found, "Target session not found"}

      {:to_receivable, false} ->
        {:error, :unprocessable_entity,
         "Target session is not active and cannot receive DMs"}
    end
  end

  defp success_response(conn, to_session, msg) do
    conn
    |> put_status(:created)
    |> json(%{
      success: true,
      message: "DM delivered to session #{to_session.id}",
      message_id: to_string(msg.id),
      message_uuid: msg.uuid
    })
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
  Body: session_id, body, sender_role (optional), recipient_role (optional),
        broadcast_to_team_id (optional) - if present, DMs all team members after posting.
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
    body = trim_param(params["body"])

    attrs = %{
      channel_id: channel_id,
      session_id: int_id,
      body: body,
      sender_role: params["sender_role"] || "agent",
      recipient_role: params["recipient_role"] || "user",
      provider: params["provider"] || "claude",
      direction: "outbound",
      status: "sent"
    }

    case ChannelMessages.create_channel_message(attrs) do
      {:ok, msg} ->
        EyeInTheSky.Events.channel_message(channel_id, msg)
        notify_channel_members(channel_id, int_id, body)

        if team_id = parse_int(params["broadcast_to_team_id"]) do
          broadcast_to_team(channel_id, int_id, team_id, body)
        end

        conn
        |> put_status(:created)
        |> json(%{success: true, message: "Message sent", message_id: to_string(msg.id)})

      {:error, _cs} ->
        {:error, "Failed to send message"}
    end
  end

  # Fan out DMs to channel members with notifications="all", excluding the sender.
  # Runs async so the channel message response is not held hostage by N serial DMs.
  defp notify_channel_members(channel_id, sender_session_id, body) do
    AsyncTask.start(fn ->
      members =
        EyeInTheSky.Channels.list_members_for_notification(channel_id, sender_session_id)

      sender_label = get_sender_name(sender_session_id)

      for member <- members do
        dm_body = "Channel notification [channel:#{channel_id}] from #{sender_label}: #{body}"

        case DMDelivery.deliver_and_persist(
               member.session_id,
               sender_session_id,
               dm_body,
               %{channel_id: channel_id, channel_notification: true}
             ) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "channel notify failed for session #{member.session_id}: #{inspect(reason)}"
            )
        end
      end
    end)

    :ok
  end

  defp get_sender_name(session_id) do
    case Sessions.get_session(session_id) do
      {:ok, session} -> session.name || "session:#{session_id}"
      _ -> "session:#{session_id}"
    end
  end

  # Fan out DMs to all active team members when broadcast_to_team_id is supplied on channel send.
  # Runs async so the channel message response is not held hostage by N serial DMs.
  defp broadcast_to_team(channel_id, sender_session_id, team_id, body) do
    AsyncTask.start(fn ->
      case Teams.get_team(team_id) do
        {:ok, team} ->
          members = Teams.list_members(team_id)
          do_team_fanout(members, sender_session_id, team, channel_id, body)

        _ ->
          Logger.warning("broadcast_to_team: team #{team_id} not found, skipping fanout")
      end
    end)
  end

  defp do_team_fanout(members, sender_session_id, team, channel_id, body) do
    if Enum.any?(members, &(&1.session_id == sender_session_id)) do
      sender_label = get_sender_name(sender_session_id)

      dm_body =
        "Broadcast from #{sender_label} [team:#{team.name}] [channel:#{channel_id}] #{body}"

      members
      |> Enum.filter(fn m ->
        m.session_id &&
          m.session_id != sender_session_id &&
          m.session &&
          m.session.status not in Sessions.terminated_statuses()
      end)
      |> Enum.each(fn member ->
        case DMDelivery.deliver_and_persist(
               member.session_id,
               sender_session_id,
               dm_body,
               %{channel_id: channel_id, broadcast: true}
             ) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "team broadcast failed for session #{member.session_id}: #{inspect(reason)}"
            )
        end
      end)
    else
      Logger.warning(
        "broadcast_to_team: session #{sender_session_id} is not a member of team #{team.id}, skipping"
      )
    end
  end

  @doc """
  POST /api/v1/channels/:channel_id/members - Add a session to a channel.
  Body: session_id (required), role (optional, default "member")
  """
  def join_channel(conn, %{"channel_id" => channel_id} = params) do
    with {:channel, channel} when not is_nil(channel) <- {:channel, Channels.get_channel(channel_id)},
         {:session_raw, raw} when not is_nil(raw) and raw != "" <- {:session_raw, params["session_id"]},
         {:session, {:ok, int_id}} <- {:session, ToolHelpers.resolve_session_int_id(raw)},
         {:session_record, {:ok, session}} <- {:session_record, Sessions.get_session(int_id)},
         {:agent_id, agent_id} when not is_nil(agent_id) <- {:agent_id, session.agent_id} do
      role = params["role"] || "member"

      case Channels.add_member(channel.id, agent_id, session.id, role) do
        {:ok, member} ->
          conn
          |> put_status(:created)
          |> json(%{
            success: true,
            message: "Joined channel #{channel.name}",
            member: ApiPresenter.present_channel_member(member)
          })

        {:error, %Ecto.Changeset{} = cs} ->
          {:error, cs}
      end
    else
      {:channel, nil} -> {:error, :not_found, "Channel not found"}
      {:session_raw, _} -> {:error, :bad_request, "session_id is required"}
      {:session, _} -> {:error, :not_found, "Session not found"}
      {:session_record, _} -> {:error, :not_found, "Session not found"}
      {:agent_id, nil} -> {:error, :unprocessable_entity, "Session has no registered agent"}
    end
  end

  @doc """
  DELETE /api/v1/channels/:channel_id/members/:session_id - Remove a session from a channel.
  """
  def leave_channel(conn, %{"channel_id" => channel_id, "session_id" => session_id_param}) do
    with {:channel, channel} when not is_nil(channel) <- {:channel, Channels.get_channel(channel_id)},
         {:session, {:ok, int_id}} <- {:session, ToolHelpers.resolve_session_int_id(session_id_param)} do
      Channels.remove_member(channel.id, int_id)
      json(conn, %{success: true, message: "Left channel #{channel.name}"})
    else
      {:channel, nil} -> {:error, :not_found, "Channel not found"}
      {:session, _} -> {:error, :not_found, "Session not found"}
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

end
