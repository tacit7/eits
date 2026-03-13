defmodule EyeInTheSkyWeb.MCP.Tools.Notify do
  @moduledoc "Create a notification visible in the EITS web UI"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.Notifications

  schema do
    field :title, :string, required: true, description: "Notification title"
    field :body, :string, description: "Optional notification body/details"

    field :category, :string, description: "Category: agent, job, or system (default: system)"

    field :resource_type, :string, description: "Type of linked resource (e.g., session, job_run)"

    field :resource_id, :string, description: "ID of linked resource"
  end

  @impl true
  def execute(params, frame) do
    opts =
      [
        category: params[:category] || "system",
        body: params[:body]
      ]
      |> maybe_add_resource(params)

    result =
      case Notifications.notify(params[:title], opts) do
        {:ok, notification} ->
          %{success: true, message: "Notification created", id: notification.id}

        {:error, cs} ->
          %{success: false, message: "Failed: #{inspect(cs.errors)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp maybe_add_resource(opts, %{resource_type: rt, resource_id: ri})
       when is_binary(rt) and is_binary(ri) do
    Keyword.put(opts, :resource, {rt, ri})
  end

  defp maybe_add_resource(opts, _), do: opts
end
