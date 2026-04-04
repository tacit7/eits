defmodule EyeInTheSkyWeb.Api.V1.NoteController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.Notes
  alias EyeInTheSky.Utils.ToolHelpers, as: Helpers

  @doc """
  GET /api/v1/notes - Search notes.
  Query params: q, limit (default 20)
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 20)

    notes =
      cond do
        params["session_id"] ->
          Notes.list_notes_for_session(params["session_id"]) |> Enum.take(limit)

        true ->
          query = params["q"] || ""
          Notes.search_notes(query) |> Enum.take(limit)
      end

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
    case Notes.get_note(note_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Note not found"})

      note ->
        json(conn, %{
          note_id: to_string(note.id),
          parent_id: note.parent_id,
          parent_type: note.parent_type,
          title: note.title,
          body: note.body,
          starred: note.starred || 0,
          created_at: to_string(note.created_at)
        })
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

  @doc """
  PATCH /api/v1/notes/:id - Update a note (body, title, starred).
  """
  def update(conn, %{"id" => note_id} = params) do
    case Notes.get_note(note_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Note not found"})

      note ->
        attrs =
          %{}
          |> Helpers.maybe_put(:body, params["body"])
          |> Helpers.maybe_put(:title, params["title"])
          |> Helpers.maybe_put(:starred, parse_starred(params["starred"]))

        case Notes.update_note(note, attrs) do
          {:ok, updated} ->
            json(conn, %{
              success: true,
              id: updated.id,
              body: updated.body,
              title: updated.title,
              starred: updated.starred || 0
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to update note", details: translate_errors(changeset)})
        end
    end
  end

  defp parse_starred(nil), do: nil
  defp parse_starred(val) when is_integer(val), do: val
  defp parse_starred(true), do: 1
  defp parse_starred(false), do: 0

  defp parse_starred(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
