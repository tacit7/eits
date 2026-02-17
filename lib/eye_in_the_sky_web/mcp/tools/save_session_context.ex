defmodule EyeInTheSkyWeb.MCP.Tools.SaveSessionContext do
  @moduledoc "Save session context in markdown format to session_context table"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EyeInTheSkyWeb.{Contexts, Sessions}

  schema do
    field :agent_id, :string, required: true, description: "Session UUID (Claude Code session ID)"
    field :session_id, :string, description: "Session UUID — alias for agent_id, takes precedence if provided"
    field :context, :string, required: true, description: "Markdown formatted context"
  end

  @impl true
  def execute(params, frame) do
    session_uuid = params[:session_id] || params[:agent_id]

    result =
      case Sessions.get_session_by_uuid(session_uuid) do
        {:ok, session} ->
          case Contexts.upsert_session_context(%{
                 session_id: session.id,
                 agent_id: session.agent_id,
                 context: params[:context]
               }) do
            {:ok, _} ->
              %{success: true, message: "Session context saved"}

            {:error, cs} ->
              %{success: false, message: "Save failed: #{inspect(cs.errors)}"}
          end

        {:error, :not_found} ->
          %{success: false, message: "Session not found: #{session_uuid}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
