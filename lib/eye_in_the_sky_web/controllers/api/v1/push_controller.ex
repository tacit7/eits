defmodule EyeInTheSkyWeb.Api.V1.PushController do
  use EyeInTheSkyWeb, :controller

  import EyeInTheSkyWeb.ControllerHelpers, only: [translate_errors: 1]

  alias EyeInTheSky.PushSubscriptions

  @doc """
  GET /api/v1/push/vapid-public-key
  Returns the VAPID public key for the browser to use when subscribing.
  """
  def vapid_public_key(conn, _params) do
    key = Application.get_env(:web_push_encryption, :vapid_details)[:public_key]
    json(conn, %{public_key: key})
  end

  @doc """
  POST /api/v1/push/subscribe
  Body: { endpoint, keys: { auth, p256dh } }
  """
  def subscribe(conn, %{"endpoint" => endpoint, "keys" => %{"auth" => auth, "p256dh" => p256dh}}) do
    case PushSubscriptions.upsert(endpoint, auth, p256dh) do
      {:ok, _} ->
        json(conn, %{success: true})

      {:error, cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, errors: translate_errors(cs)})
    end
  end

  def subscribe(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{success: false, message: "endpoint and keys.auth/p256dh required"})
  end

  @doc """
  DELETE /api/v1/push/subscribe
  Body: { endpoint }
  """
  def unsubscribe(conn, %{"endpoint" => endpoint}) do
    PushSubscriptions.delete(endpoint)
    json(conn, %{success: true})
  end

  def unsubscribe(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{success: false, message: "endpoint required"})
  end
end
