defmodule EyeInTheSkyWeb.MCP.Tools.SessionSearch do
  @moduledoc "Full-text search across sessions"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :query, :string, required: true, description: "Search query for FTS5 search"
    field :limit, :integer, description: "Maximum results (default: 20)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Agents

    query = params["query"]
    limit = params["limit"] || 20
    results = Agents.list_agents_filtered(%{"search" => query})
    results = Enum.take(results, limit)

    result = %{
      success: true,
      message: "Found #{length(results)} session(s) matching '#{query}'",
      results:
        Enum.map(results, fn a ->
          %{
            id: a.id,
            uuid: a.uuid,
            description: a.description,
            status: a.status
          }
        end)
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
