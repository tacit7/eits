defmodule EyeInTheSkyWeb.MCP.Tools.NoteAdd do
  @moduledoc "Add note to session"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :parent_id, :string,
      description: "Parent entity identifier. Defaults to current session UUID."

    field :parent_type, :string,
      description: "Parent entity type (session, agent, task, project, system). Defaults to 'session'."

    field :body, :string, required: true, description: "Note content"
    field :title, :string, description: "Note title (optional)"
    field :starred, :integer, description: "Starred flag (0 or 1, default 0)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Notes

    parent_id = params[:parent_id] || frame.assigns[:eits_session_id]
    parent_type = normalize_parent_type(params[:parent_type] || "session")

    attrs = %{
      parent_id: parent_id,
      parent_type: parent_type,
      body: params[:body],
      title: params[:title],
      starred: params[:starred] || 0
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

  defp normalize_parent_type("sessions"), do: "session"
  defp normalize_parent_type("agents"), do: "agent"
  defp normalize_parent_type("tasks"), do: "task"
  defp normalize_parent_type("projects"), do: "project"
  defp normalize_parent_type(type), do: type
end
