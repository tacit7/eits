defmodule EyeInTheSkyWeb.MCP.Tools.SessionSearch do
  @moduledoc "Full-text search across sessions"

  use Anubis.Server.Component, type: :tool

  alias EyeInTheSkyWeb.MCP.Tools.ResponseHelper

  schema do
    field :query, :string, required: true, description: "Search query for FTS5 search"
    field :limit, :integer, description: "Maximum results (default: 20)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Sessions

    query = params[:query] || ""
    limit = params[:limit] || 20
    results = Sessions.list_sessions_filtered(search_query: query, limit: limit)

    result = %{
      success: true,
      message: "Found #{length(results)} session(s) matching '#{query}'",
      results:
        Enum.map(results, fn s ->
          %{
            id: s.id,
            uuid: s.uuid,
            description: s.description,
            status: s.status
          }
        end)
    }

    response = ResponseHelper.json_response(result)
    {:reply, response, frame}
  end
end
