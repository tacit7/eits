defmodule EyeInTheSkyWeb.MCP.Tools.AgentCancel do
  @moduledoc "Cancel the in-flight SDK process for an agent worker by session ID (int or UUID)"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.MCP.Tools.Helpers

  schema do
    field :session_id, :string,
      required: true,
      description: "Target session ID (integer or UUID)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Claude.AgentManager

    result =
      case Helpers.resolve_session_int_id(params[:session_id]) do
        {:ok, int_id} ->
          case AgentManager.cancel_session(int_id) do
            :ok -> %{success: true, message: "Cancelled session #{int_id}"}
            {:error, :not_found} -> %{success: false, message: "No active worker for session #{int_id}"}
          end

        {:error, reason} ->
          %{success: false, message: reason}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
