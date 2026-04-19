defmodule EyeInTheSkyWeb.Api.V1.NotificationController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers, only: [maybe_opt: 3, translate_errors: 1]

  alias EyeInTheSky.Notifications

  @doc """
  POST /api/v1/notifications
  Body: title (required), body, category (agent|job|system), resource_type, resource_id
  """
  def create(conn, params) do
    title = params["title"]

    if is_nil(title) || title == "" do
      conn
      |> put_status(:bad_request)
      |> json(%{success: false, message: "title is required"})
    else
      resource =
        params["resource_type"] &&
          params["resource_id"] &&
          {params["resource_type"], params["resource_id"]}

      opts =
        []
        |> maybe_opt(:body, params["body"])
        |> Keyword.put(:category, params["category"] || "system")
        |> maybe_opt(:resource, resource)

      case Notifications.notify(title, opts) do
        {:ok, notification} ->
          json(conn, %{success: true, message: "Notification created", id: notification.id})

        {:error, cs} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            message: "Invalid notification data",
            errors: translate_errors(cs)
          })
      end
    end
  end
end
