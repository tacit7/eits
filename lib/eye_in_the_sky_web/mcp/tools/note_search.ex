defmodule EyeInTheSkyWeb.MCP.Tools.NoteSearch do
  @moduledoc "Full-text search across notes"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :query, :string, required: true, description: "Search query for FTS5 search"
    field :limit, :integer, description: "Maximum results (default: 20)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Notes

    query = params["query"]
    notes = Notes.search_notes(query)

    limit = params["limit"] || 20
    notes = Enum.take(notes, limit)

    result = %{
      success: true,
      message: "Found #{length(notes)} note(s) matching '#{query}'",
      results:
        Enum.map(notes, fn n ->
          %{
            id: n.id,
            uuid: n.uuid,
            parent_id: n.parent_id,
            parent_type: n.parent_type,
            title: n.title,
            body: n.body,
            starred: n.starred || 0
          }
        end)
    }

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
