defmodule EyeInTheSkyWeb.PushSubscriptions do
  @moduledoc """
  Manages Web Push subscriptions and sends push notifications.
  """

  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.PushSubscriptions.PushSubscription
  require Logger

  def upsert(endpoint, auth, p256dh) do
    case Repo.get_by(PushSubscription, endpoint: endpoint) do
      nil ->
        %PushSubscription{}
        |> PushSubscription.changeset(%{endpoint: endpoint, auth: auth, p256dh: p256dh})
        |> Repo.insert()

      existing ->
        existing
        |> PushSubscription.changeset(%{auth: auth, p256dh: p256dh})
        |> Repo.update()
    end
  end

  def delete(endpoint) do
    case Repo.get_by(PushSubscription, endpoint: endpoint) do
      nil -> {:ok, :not_found}
      sub -> Repo.delete(sub)
    end
  end

  def list_all do
    Repo.all(PushSubscription)
  end

  @doc """
  Send a push notification to all subscribed devices.
  """
  def broadcast(title, body \\ nil) do
    subs = list_all()

    payload =
      Jason.encode!(%{
        title: title,
        body: body || title,
        icon: "/images/logo.svg"
      })

    for sub <- subs do
      subscription = %{
        endpoint: sub.endpoint,
        keys: %{
          auth: sub.auth,
          p256dh: sub.p256dh
        }
      }

      case WebPushEncryption.send_web_push(payload, subscription) do
        {:ok, _} ->
          :ok

        {:error, %{status_code: code}} when code in [404, 410] ->
          # Subscription expired — clean it up
          Repo.delete(sub)

        {:error, reason} ->
          Logger.warning("Push notification failed for #{sub.endpoint}: #{inspect(reason)}")
      end
    end

    :ok
  end
end
