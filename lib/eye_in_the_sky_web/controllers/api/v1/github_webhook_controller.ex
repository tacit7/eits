defmodule EyeInTheSkyWeb.Api.V1.GithubWebhookController do
  use EyeInTheSkyWeb, :controller

  require Logger

  alias EyeInTheSky.Events
  alias EyeInTheSky.Github.Webhook
  alias EyeInTheSky.Github.WebhookDeliveries

  def receive(conn, _params) do
    secret = Application.get_env(:eye_in_the_sky, :github_webhook_secret, "")
    raw_body = conn.assigns[:raw_body] || ""

    sig_header = get_req_header(conn, "x-hub-signature-256") |> List.first()

    with :ok <- Webhook.verify(sig_header, raw_body, secret),
         [event_header] <- get_req_header(conn, "x-github-event"),
         [delivery_id] <- get_req_header(conn, "x-github-delivery") do
      hook_id = get_req_header(conn, "x-github-hook-id") |> List.first()
      payload = resolve_payload(conn.body_params)
      action = payload["action"]
      event_type = Webhook.normalize_event_type(event_header, action)
      repo = get_in(payload, ["repository", "full_name"])
      sender = get_in(payload, ["sender", "login"])

      attrs = %{
        delivery_id: delivery_id,
        hook_id: hook_id,
        event_type: event_type,
        event_header: event_header,
        action: action,
        repository_full_name: repo,
        sender_login: sender,
        payload: payload,
        received_at: DateTime.utc_now()
      }

      case WebhookDeliveries.insert(attrs) do
        {:ok, delivery} ->
          Events.github_webhook_received(delivery.delivery_id)
          send_resp(conn, 202, "")

        {:duplicate, _delivery} ->
          send_resp(conn, 202, "")

        {:error, changeset} ->
          Logger.error("Failed to insert webhook delivery: #{inspect(changeset)}")
          send_resp(conn, 500, "")
      end
    else
      :error ->
        send_resp(conn, 401, "")

      [] ->
        send_resp(conn, 400, "")
    end
  end

  # smee forwards payloads as form-encoded `payload=<json>` instead of raw JSON.
  defp resolve_payload(%{"payload" => json}) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  defp resolve_payload(params), do: params || %{}
end
