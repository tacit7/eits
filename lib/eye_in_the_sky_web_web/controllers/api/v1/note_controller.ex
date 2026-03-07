defmodule EyeInTheSkyWebWeb.Api.V1.NoteController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.Notes

  @doc """
  GET /api/v1/notes - Search notes.
  Query params: q, limit (default 20)
  """
  def index(conn, params) do
    query = params["q"] || ""
    limit = parse_int(params["limit"], 20)
    notes = Notes.search_notes(query) |> Enum.take(limit)

    json(conn, %{
      success: true,
      message: "Found #{length(notes)} note(s)",
      results:
        Enum.map(notes, fn n ->
          %{
            id: n.id,
            parent_id: n.parent_id,
            parent_type: n.parent_type,
            title: n.title,
            body: n.body,
            starred: n.starred || 0
          }
        end)
    })
  end

  @doc """
  GET /api/v1/notes/:id - Retrieve a note by ID.
  """
  def show(conn, %{"id" => note_id}) do
    try do
      note = Notes.get_note!(note_id)

      json(conn, %{
        note_id: to_string(note.id),
        parent_id: note.parent_id,
        parent_type: note.parent_type,
        title: note.title,
        body: note.body,
        starred: note.starred || 0,
        created_at: to_string(note.created_at)
      })
    rescue
      Ecto.NoResultsError ->
        conn |> put_status(:not_found) |> json(%{error: "Note not found"})
    end
  end

  @doc """
  POST /api/v1/notes - Add a note.

  Accepts parent_id, parent_type, title (optional), body, starred (optional).
  Normalizes parent_type plurals (e.g. "sessions" -> "session") to match schema validation.
  """
  def create(conn, params) do
    # Normalize parent_type: the MCP tools send plural ("sessions", "agents", "tasks")
    # but the Note schema validates singular
    parent_type = normalize_parent_type(params["parent_type"])

    attrs = %{
      parent_type: parent_type,
      parent_id: to_string(params["parent_id"]),
      title: params["title"],
      body: params["body"],
      starred: params["starred"] || 0
    }

    case Notes.create_note(attrs) do
      {:ok, note} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: note.id,
          parent_type: note.parent_type,
          parent_id: note.parent_id,
          title: note.title,
          body: note.body,
          starred: note.starred
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create note", details: translate_errors(changeset)})
    end
  end

  # Normalize plural parent_type to singular for schema validation
  defp normalize_parent_type("sessions"), do: "session"
  defp normalize_parent_type("agents"), do: "agent"
  defp normalize_parent_type("tasks"), do: "task"
  defp normalize_parent_type(type), do: type

  defp parse_int(nil, default), do: default
  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp translate_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
