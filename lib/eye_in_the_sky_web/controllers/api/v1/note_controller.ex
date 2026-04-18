defmodule EyeInTheSkyWeb.Api.V1.NoteController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.Notes
  alias EyeInTheSky.Utils.ToolHelpers, as: Helpers
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/notes - Search notes.
  Query params: q, limit (default 20)
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 20)

    notes =
      if params["session_id"] do
        Notes.list_notes_for_session(params["session_id"]) |> Enum.take(limit)
      else
        query = params["q"] || ""
        Notes.search_notes(query) |> Enum.take(limit)
      end

    json(conn, %{
      success: true,
      message: "Found #{length(notes)} note(s)",
      results: Enum.map(notes, &ApiPresenter.present_note/1)
    })
  end

  @doc """
  GET /api/v1/notes/:id - Retrieve a note by ID.
  """
  def show(conn, %{"id" => note_id}) do
    case Notes.get_note(note_id) do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Note not found"})

      {:ok, note} ->
        json(conn, %{
          note_id: to_string(note.id),
          parent_id: note.parent_id,
          parent_type: note.parent_type,
          title: note.title,
          body: note.body,
          starred: note.starred || false,
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
      title: trim_param(params["title"]),
      body: trim_param(params["body"]),
      starred: params["starred"] || false
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
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Note not found"})

      {:ok, note} ->
        attrs =
          %{}
          |> Helpers.maybe_put(:body, trim_param(params["body"]))
          |> Helpers.maybe_put(:title, trim_param(params["title"]))

        attrs =
          case parse_starred(params["starred"]) do
            {:ok, val} -> Map.put(attrs, :starred, val)
            :error -> attrs
          end

        case Notes.update_note(note, attrs) do
          {:ok, updated} ->
            json(conn, %{
              success: true,
              id: updated.id,
              body: updated.body,
              title: updated.title,
              starred: updated.starred || false
            })

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to update note", details: translate_errors(changeset)})
        end
    end
  end
end
