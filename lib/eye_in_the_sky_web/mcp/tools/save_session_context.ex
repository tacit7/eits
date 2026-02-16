defmodule EyeInTheSkyWeb.MCP.Tools.SaveSessionContext do
  @moduledoc "Save session context in markdown format to session_context table"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :agent_id, :string, required: true, description: "Agent UUID identifier"
    field :session_id, :string, description: "Session UUID (optional)"
    field :context, :string, required: true, description: "Markdown formatted context"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Contexts

    result =
      case Contexts.upsert_session_context(%{
             session_id: params["session_id"] || params["agent_id"],
             context: params["context"]
           }) do
        {:ok, _} ->
          %{success: true, message: "Session context saved"}

        {:error, cs} ->
          %{success: false, message: "Save failed: #{inspect(cs.errors)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
