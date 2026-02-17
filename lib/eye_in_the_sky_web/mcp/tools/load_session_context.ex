defmodule EyeInTheSkyWeb.MCP.Tools.LoadSessionContext do
  @moduledoc "Load session context from session_context table"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.{Contexts, Sessions}

  schema do
    field :agent_id, :string, required: true, description: "Session UUID (Claude Code session ID)"

    field :session_id, :string,
      description: "Session UUID — alias for agent_id, takes precedence if provided"
  end

  @impl true
  def execute(params, frame) do
    session_uuid = params[:session_id] || params[:agent_id]

    result =
      case Sessions.get_session_by_uuid(session_uuid) do
        {:ok, session} ->
          case Contexts.get_session_context(session.id) do
            nil ->
              %{success: false, message: "No context found for session #{session_uuid}"}

            ctx ->
              %{
                success: true,
                message: "Context loaded",
                context: ctx.context,
                created_at: to_string(ctx.created_at),
                updated_at: to_string(ctx.updated_at)
              }
          end

        {:error, :not_found} ->
          %{success: false, message: "No context found for session #{session_uuid}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
