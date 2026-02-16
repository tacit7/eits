defmodule EyeInTheSkyWeb.MCP.Tools.NoteAdd do
  @moduledoc "Add note to session"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :parent_id, :string, required: true, description: "Parent entity identifier (session, agent, context, etc)"
    field :parent_type, :string, required: true, description: "Parent entity type (sessions, agents, contexts, etc)"
    field :body, :string, required: true, description: "Note content"
    field :title, :string, description: "Note title (optional)"
    field :starred, :integer, description: "Starred flag (0 or 1, default 0)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Notes

    attrs = %{
      parent_id: params["parent_id"],
      parent_type: params["parent_type"],
      body: params["body"],
      title: params["title"],
      starred: params["starred"] || 0
    }

    result =
      case Notes.create_note(attrs) do
        {:ok, note} ->
          %{success: true, message: "Note created", id: note.id, uuid: note.uuid}

        {:error, cs} ->
          %{success: false, message: "Failed: #{inspect(cs.errors)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
