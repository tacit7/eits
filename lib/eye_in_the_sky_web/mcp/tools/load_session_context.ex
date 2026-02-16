defmodule EyeInTheSkyWeb.MCP.Tools.LoadSessionContext do
  @moduledoc "Load session context from session_context table"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :agent_id, :string, required: true, description: "Agent UUID identifier"
    field :session_id, :string, description: "Specific session ID (optional, loads latest if omitted)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Contexts

    session_id = params["session_id"] || params["agent_id"]

    result =
      case Contexts.get_session_context(session_id) do
        nil ->
          %{success: false, message: "No context found for session #{session_id}"}

        ctx ->
          %{
            success: true,
            message: "Context loaded",
            context: ctx.context,
            created_at: to_string(ctx.inserted_at),
            updated_at: to_string(ctx.updated_at)
          }
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
