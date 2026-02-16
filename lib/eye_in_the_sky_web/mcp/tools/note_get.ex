defmodule EyeInTheSkyWeb.MCP.Tools.NoteGet do
  @moduledoc "Retrieve note by ID"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :note_id, :string, required: true, description: "Note ID to retrieve"
  end

  @impl true
  def execute(%{"note_id" => note_id}, frame) do
    alias EyeInTheSkyWeb.Notes

    result =
      try do
        note = Notes.get_note!(note_id)

        %{
          note_id: to_string(note.id),
          parent_id: note.parent_id,
          parent_type: note.parent_type,
          title: note.title,
          body: note.body,
          starred: note.starred || 0,
          created_at: to_string(note.inserted_at)
        }
      rescue
        Ecto.NoResultsError ->
          %{success: false, message: "Note not found: #{note_id}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
