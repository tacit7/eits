defmodule EyeInTheSkyWeb.Api.V1.MessagingController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  require Logger
  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.{Messages, Sessions}
  alias EyeInTheSky.Messaging.DMDelivery
  alias EyeInTheSkyWeb.MCP.Tools.SessionResolver
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
      with {:ok, session} <- SessionResolver.resolve(session_raw),
           {:ok, from_id} <- SessionResolver.resolve_optional_int(from_raw),
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

  @doc """
  GET /api/v1/dm/:id - Fetch a single DM by integer ID.
  The caller must be the recipient (to_session_id matches the session param or current session).
  Query params:
    - session (optional): integer session ID or UUID of the requesting session (default: resolved from auth)
  """
  def show_dm(conn, %{"id" => id} = params) do
    session_raw = params["session"] || get_req_header(conn, "x-eits-session") |> List.first()

    case parse_int(id) do
      nil ->
        {:error, :bad_request, "id must be an integer"}

      msg_id ->
        case Messages.get_message(msg_id) do
          {:error, :not_found} ->
            {:error, :not_found, "DM not found"}

          {:ok, msg} ->
            # If caller provides a session, verify they are the recipient
            with {:ok, caller_id} <- resolve_caller_session(session_raw, msg) do
              if caller_id != nil and msg.to_session_id != caller_id do
                {:error, :forbidden, "You are not the recipient of this message"}
              else
                json(conn, %{
                  id: msg.id,
                  uuid: msg.uuid,
                  body: msg.body,
                  from_session_id: msg.from_session_id,
                  to_session_id: msg.to_session_id,
                  inserted_at: msg.inserted_at
                })
              end
            end
        end
    end
  end

  defp resolve_caller_session(nil, _msg), do: {:ok, nil}
  defp resolve_caller_session("", _msg), do: {:ok, nil}

  defp resolve_caller_session(raw, _msg) do
    case SessionResolver.resolve(raw) do
      {:ok, session} -> {:ok, session.id}
      {:error, _} -> {:ok, nil}
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
    SessionResolver.resolve_with_agent_fallback(raw)
  end

  defp resolve_session_target(%{raw: raw, kind: :to}) do
    SessionResolver.resolve(raw)
  end

  # waiting = sdk-cli session ended and queued for resume; DM will be delivered on next wakeup
  @receivable_statuses ~w(working idle waiting)

  defp do_dm(conn, params, from_raw, to_raw) do
    with {:ok, from_session} <- resolve_dm_sender(from_raw),
         :ok <- check_sender_not_terminated(from_session),
         {:ok, to_session} <- resolve_dm_receiver(to_raw),
         :ok <- check_receiver_reachable(to_session) do
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
              maybe_send_test_message_auto_reply(from_session, to_session, params["message"])
              dm_success(conn, to_session, msg)

            {:error, :queue_full} ->
              Logger.warning("DM queue full for session #{to_session.id}")

              conn
              |> put_status(503)
              |> json(%{
                error: "queue_full",
                reachable: true,
                message: "Target session queue is full; retry later"
              })

            {:error, reason} when reason in [:worker_not_found, :not_running] ->
              Logger.warning(
                "DM worker unreachable for session #{to_session.id}: #{inspect(reason)}"
              )

              conn
              |> put_status(503)
              |> json(%{
                error: "target_session_unreachable",
                reachable: false,
                message: "Target session worker is not running"
              })

            {:error, {:worker_exit, exit_reason}} ->
              Logger.error(
                "DM worker exited for session #{to_session.id}: #{inspect(exit_reason)}"
              )

              conn
              |> put_status(503)
              |> json(%{
                error: "target_session_unreachable",
                reachable: false,
                message: "Target session worker crashed"
              })

            {:error, :invalid_message} ->
              {:error, :unprocessable_entity, "Invalid message payload"}

            {:error, reason} ->
              Logger.error("DM delivery failed for session #{to_session.id}: #{inspect(reason)}")

              conn
              |> put_status(503)
              |> json(%{
                error: "delivery_failed",
                reachable: false,
                message: "Failed to deliver message"
              })
          end

        existing ->
          dm_success(conn, to_session, existing)
      end
    else
      {:error, :sender_not_found} ->
        {:error, :not_found, "Sender session not found"}

      {:error, :sender_terminated} ->
        {:error, :unprocessable_entity, "Sender session is terminated and cannot send DMs"}

      {:error, :receiver_not_found} ->
        {:error, :not_found, "Target session not found"}

      {:error, :receiver_not_receivable} ->
        {:error, :unprocessable_entity,
         "Target session is terminated (completed or failed) and cannot receive DMs"}
    end
  end

  defp resolve_dm_sender(raw) do
    case resolve_session_target(%{raw: raw, kind: :from}) do
      {:ok, session} -> {:ok, session}
      {:error, :not_found} -> {:error, :sender_not_found}
    end
  end

  defp check_sender_not_terminated(session) do
    if session.status in Sessions.terminated_statuses(),
      do: {:error, :sender_terminated},
      else: :ok
  end

  defp resolve_dm_receiver(raw) do
    case resolve_session_target(%{raw: raw, kind: :to}) do
      {:ok, session} -> {:ok, session}
      {:error, :not_found} -> {:error, :receiver_not_found}
    end
  end

  defp check_receiver_reachable(session) do
    if session.status in @receivable_statuses,
      do: :ok,
      else: {:error, :receiver_not_receivable}
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

  defp maybe_send_test_message_auto_reply(from_session, to_session, raw_message) do
    if trim_param(raw_message) == "test message" do
      reply_sender_name = ApiPresenter.resolve_session_sender_name(to_session)

      reply_body =
        "DM from:#{reply_sender_name} (session:#{to_session.uuid}) Codex received your message and is responding."

      reply_metadata = %{
        sender_name: reply_sender_name,
        from_session_uuid: to_session.uuid,
        to_session_uuid: from_session.uuid,
        response_required: false,
        auto_reply: true
      }

      case Messages.find_recent_dm(from_session.id, reply_body, seconds: 30) do
        nil ->
          case DMDelivery.deliver_and_persist(
                 from_session.id,
                 to_session.id,
                 reply_body,
                 reply_metadata
               ) do
            {:ok, _msg} ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "DM auto-reply failed from session #{to_session.id} to #{from_session.id}: #{inspect(reason)}"
              )
          end

        _existing ->
          :ok
      end
    end
  end
end
