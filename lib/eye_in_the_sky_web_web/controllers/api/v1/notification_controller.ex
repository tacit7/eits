defmodule EyeInTheSkyWebWeb.Api.V1.NotificationController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.Notifications

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
      opts =
        []
        |> then(fn o -> if params["body"], do: Keyword.put(o, :body, params["body"]), else: o end)
        |> then(fn o -> Keyword.put(o, :category, params["category"] || "system") end)
        |> then(fn o ->
          if params["resource_type"] && params["resource_id"] do
            Keyword.put(o, :resource, {params["resource_type"], params["resource_id"]})
          else
            o
          end
        end)

      case Notifications.notify(title, opts) do
        {:ok, notification} ->
          json(conn, %{success: true, message: "Notification created", id: notification.id})

        {:error, cs} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{success: false, message: "Failed: #{inspect(cs.errors)}"})
      end
    end
  end
end
