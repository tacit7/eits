defmodule EyeInTheSkyWeb.Api.V1.NoteController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.Notes
  alias EyeInTheSky.Tasks
  alias EyeInTheSky.Utils.ToolHelpers, as: Helpers
  alias EyeInTheSkyWeb.Api.V1.ProjectScope
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/notes - Search notes.
  Query params: q, limit (default 20), source_session_uuid (filter by author), session_id, task_id, project_id, starred
  """
  def index(conn, params) do
    limit = parse_int(params["limit"], 20)
    starred_only = params["starred"] in ["true", "1"]
    source_session_uuid = params["source_session_uuid"]

    with {:ok, project_id} <- ProjectScope.authorize_project_id(conn, params, params["project_id"]) do
      notes =
        cond do
          source_session_uuid ->
            Notes.list_notes_by_source_session(source_session_uuid,
              starred: starred_only,
              parent_type: params["parent_type"],
              parent_id: params["parent_id"],
              limit: limit
            )

          params["session_id"] ->
            Notes.list_notes_for_session(params["session_id"], limit: limit, starred: starred_only)

          params["task_id"] ->
            case Tasks.get_task_ids(params["task_id"]) do
              {:ok, {task_id, _uuid}} ->
                Notes.list_notes_for_task(task_id, starred: starred_only)

              {:error, :not_found} ->
                []
            end

          true ->
            query = params["q"] || ""

            Notes.search_notes(query, [],
              limit: limit,
              project_id: project_id,
              starred: starred_only
            )
        end

      json(conn, %{
        success: true,
        message: "Found #{length(notes)} note(s)",
        results: Enum.map(notes, &ApiPresenter.present_note/1)
      })
    end
  end

  @doc """
  GET /api/v1/notes/:id - Retrieve a note by ID.
  """
  def show(conn, %{"id" => note_id}) do
    case Notes.get_note(note_id) do
      {:error, :not_found} ->
        {:error, :not_found, "Note not found"}

      {:ok, note} ->
        json(conn, ApiPresenter.present_note(note))
    end
  end

  @doc """
  POST /api/v1/notes - Add a note.

  Accepts parent_id, parent_type, title (optional), body, starred (optional),
  source_session_uuid (optional). Normalizes parent_type plurals (e.g. "sessions" ->
  "session") to match schema validation.

  source_session_uuid resolution order: explicit `source_session_uuid` param first,
  then auto-stamped from the `x-eits-session` request header (sent by the eits CLI
  whenever EITS_SESSION_UUID is set). Either may be absent — human/manual note
  creation has no session context, and that's fine.
  """
  def create(conn, params) do
    # Normalize parent_type: the MCP tools send plural ("sessions", "agents", "tasks")
    # but the Note schema validates singular
    parent_type = normalize_parent_type(params["parent_type"])

    # Prefer an explicit source_session_uuid param; fall back to auto-stamping from
    # the request header (session context) when the caller doesn't pass one.
    source_session_uuid =
      trim_param(params["source_session_uuid"]) ||
        conn |> Plug.Conn.get_req_header("x-eits-session") |> List.first()

    attrs = %{
      parent_type: parent_type,
      parent_id: to_string(params["parent_id"]),
      title: trim_param(params["title"]),
      body: trim_param(params["body"]),
      starred: params["starred"] || false,
      source_session_uuid: source_session_uuid
    }

    case Notes.create_note(attrs) do
      {:ok, note} ->
        conn
        |> put_status(:created)
        |> json(ApiPresenter.present_note(note))

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create note", details: translate_errors(changeset)})
    end
  end

  @doc """
  PATCH /api/v1/notes/:id - Update a note (body, title, starred, parent_type, parent_id).
  """
  def update(conn, %{"id" => note_id} = params) do
    case Notes.get_note(note_id) do
      {:error, :not_found} ->
        {:error, :not_found, "Note not found"}

      {:ok, note} ->
        attrs =
          %{}
          |> Helpers.maybe_put(:body, trim_param(params["body"]))
          |> Helpers.maybe_put(:title, trim_param(params["title"]))
          |> Helpers.maybe_put(:parent_type, normalize_parent_type(params["parent_type"]))
          |> Helpers.maybe_put(:parent_id, trim_param(params["parent_id"]))

        attrs =
          case parse_starred(params["starred"]) do
            {:ok, val} -> Map.put(attrs, :starred, val)
            :error -> attrs
          end

        case Notes.update_note(note, attrs) do
          {:ok, updated} ->
            json(conn, ApiPresenter.present_note(updated))

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to update note", details: translate_errors(changeset)})
        end
    end
  end
end
