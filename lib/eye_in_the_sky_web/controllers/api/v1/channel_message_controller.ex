defmodule EyeInTheSkyWeb.Api.V1.ChannelMessageController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  require Logger
  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{AsyncTask, ChannelMessages, Sessions, Teams}
  alias EyeInTheSky.Claude.ChannelFanout
  alias EyeInTheSky.Messaging.DMDelivery
  alias EyeInTheSky.Utils.ToolHelpers
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  POST /api/v1/channels/:channel_id/messages - Send a message to a channel.
  Body: session_id, body, sender_role (optional), recipient_role (optional),
        broadcast_to_team_id (optional) - if present, DMs all team members after posting.
  """
  def create(conn, %{"channel_id" => channel_id} = params) do
    with :ok <- validate_required(params["session_id"], "session_id"),
         :ok <- validate_required(params["body"], "body") do
      case ToolHelpers.resolve_session_int_id(params["session_id"]) do
        {:ok, int_id} -> do_create(conn, channel_id, int_id, params)
        {:error, reason} -> {:error, :not_found, reason}
      end
    end
  end

  @doc """
  GET /api/v1/channels/:channel_id/messages - List recent messages for a channel.
  Query params:
    - limit (optional, default 20, max 200)
    - since (optional) — return only messages with id > since (integer message ID); useful for catch-up polling
    - before (optional) — return only messages with id < before (scroll-up pagination)
  """
  def index(conn, %{"channel_id" => channel_id} = params) do
    limit =
      case parse_int(params["limit"], 20) do
        n when n > 0 and n <= 200 -> n
        _ -> 20
      end

    opts =
      [limit: limit]
      |> then(fn o ->
        case parse_int(params["since"]) do
          nil -> o
          id -> Keyword.put(o, :after_id, id)
        end
      end)
      |> then(fn o ->
        case parse_int(params["before"]) do
          nil -> o
          id -> Keyword.put(o, :before_id, id)
        end
      end)

    messages = ChannelMessages.list_messages_for_channel(channel_id, opts)

    json(conn, %{
      success: true,
      channel_id: channel_id,
      count: length(messages),
      messages: Enum.map(messages, &ApiPresenter.present_channel_message/1)
    })
  end

  defp do_create(conn, channel_id, int_id, params) do
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
        notify_channel_members(channel_id, int_id, body)
        ChannelFanout.fanout_all(channel_id, body, int_id)

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

  # Fan out DMs to all active team members when broadcast_to_team_id is supplied.
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
end
