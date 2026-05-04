defmodule EyeInTheSkyWeb.Api.V1.MessagingController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  require Logger
  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Agents, Messages, Sessions}
  alias EyeInTheSky.Messaging.DMDelivery
  alias EyeInTheSky.Utils.ToolHelpers
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/dm - List inbound DMs for a session.
  Query params:
    - session (required): integer session ID or UUID
    - limit (optional): max messages to return, default 20
    - since (optional): ISO8601 timestamp; return only messages inserted after this time
  """
  def list_dms(conn, params) do
    session_raw = params["session"] || params["session_id"]
    from_raw = params["from"] || params["from_session_id"]
    limit = min(parse_int(params["limit"], 20), 100)

    if is_nil(session_raw) or session_raw == "" do
      {:error, :bad_request, "session is required"}
    else
      with {:ok, session} <- Sessions.resolve(session_raw),
           {:ok, from_id} <- resolve_optional_session_id(from_raw),
           {:ok, since_dt} <- parse_since(params["since"]) do
        opts = [from_session_id: from_id, since: since_dt]
        messages = Messages.list_inbound_dms(session.id, limit, opts)

        json(conn, %{
          session_id: session.id,
          session_uuid: session.uuid,
          count: length(messages),
          filter_from: from_raw,
          filter_since: params["since"],
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

  defp parse_since(nil), do: {:ok, nil}
  defp parse_since(""), do: {:ok, nil}

  defp parse_since(raw) do
    case DateTime.from_iso8601(raw) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:error, :bad_request, "since must be a valid ISO8601 timestamp"}
    end
  end

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

  # :from also falls back to agent UUID lookup (legacy sender_id).
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

  # waiting = sdk-cli session ended and queued for resume; DM will be delivered on next wakeup
  @receivable_statuses ~w(working idle waiting)

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

      metadata = %{
        sender_name: sender_name,
        from_session_uuid: from_session.uuid,
        to_session_uuid: to_session.uuid,
        response_required: response_required
      }

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
              dm_success(conn, to_session, msg)

            {:error, :queue_full} ->
              Logger.warning("DM queue full for session #{to_session.id}")
              conn |> put_status(503) |> json(%{error: "queue_full", reachable: true, message: "Target session queue is full; retry later"})

            {:error, reason} when reason in [:worker_not_found, :not_running] ->
              Logger.warning("DM worker unreachable for session #{to_session.id}: #{inspect(reason)}")
              conn |> put_status(503) |> json(%{error: "target_session_unreachable", reachable: false, message: "Target session worker is not running"})

            {:error, {:worker_exit, exit_reason}} ->
              Logger.error("DM worker exited for session #{to_session.id}: #{inspect(exit_reason)}")
              conn |> put_status(503) |> json(%{error: "target_session_unreachable", reachable: false, message: "Target session worker crashed"})

            {:error, :invalid_message} ->
              {:error, :unprocessable_entity, "Invalid message payload"}

            {:error, reason} ->
              Logger.error("DM delivery failed for session #{to_session.id}: #{inspect(reason)}")
              conn |> put_status(503) |> json(%{error: "delivery_failed", reachable: false, message: "Failed to deliver message"})
          end

        existing ->
          dm_success(conn, to_session, existing)
      end
    else
      {:from, {:error, :not_found}} ->
        {:error, :not_found, "Sender session not found"}

      {:from_active, true} ->
        {:error, :unprocessable_entity, "Sender session is terminated and cannot send DMs"}

      {:to, {:error, :not_found}} ->
        {:error, :not_found, "Target session not found"}

      {:to_receivable, false} ->
        {:error, :unprocessable_entity, "Target session is terminated (completed or failed) and cannot receive DMs"}
    end
  end

  defp dm_success(conn, to_session, msg) do
    conn
    |> put_status(:created)
    |> json(%{
      success: true,
      reachable: true,
      message: "DM delivered to session #{to_session.id}",
      message_id: to_string(msg.id),
      message_uuid: msg.uuid
    })
  end
end
