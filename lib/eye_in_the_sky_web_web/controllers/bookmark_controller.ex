defmodule EyeInTheSkyWebWeb.BookmarkController do
  use EyeInTheSkyWebWeb, :controller

  import EyeInTheSkyWebWeb.ControllerHelpers

  alias EyeInTheSkyWeb.Bookmarks
  alias EyeInTheSkyWeb.Bookmarks.Bookmark

  @doc """
  Lists bookmarks with optional filters.

  Query params:
  - type: bookmark_type filter
  - category: category filter
  - project_id: project filter
  - agent_id: agent filter
  - limit: max results
  """
  def index(conn, params) do
    opts =
      []
      |> add_opt(:bookmark_type, params["type"])
      |> add_opt(:category, params["category"])
      |> add_opt(:project_id, parse_int(params["project_id"]))
      |> add_opt(:agent_id, params["agent_id"])
      |> add_opt(:limit, parse_int(params["limit"]))

    bookmarks = Bookmarks.list_bookmarks(opts)

    json(conn, %{bookmarks: render_bookmarks(bookmarks)})
  end

  @doc """
  Creates a new bookmark.
  """
  def create(conn, bookmark_params) do
    case Bookmarks.create_bookmark(bookmark_params) do
      {:ok, bookmark} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: bookmark.id,
          bookmark: render_bookmark(bookmark)
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  @doc """
  Shows a single bookmark.
  """
  def show(conn, %{"id" => id}) do
    bookmark = Bookmarks.get_bookmark!(id)

    # Touch the bookmark to update accessed_at
    {:ok, bookmark} = Bookmarks.touch_bookmark(bookmark)

    json(conn, %{bookmark: render_bookmark(bookmark)})
  end

  @doc """
  Updates a bookmark.
  """
  def update(conn, %{"id" => id} = params) do
    bookmark = Bookmarks.get_bookmark!(id)

    case Bookmarks.update_bookmark(bookmark, params) do
      {:ok, bookmark} ->
        json(conn, %{bookmark: render_bookmark(bookmark)})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  @doc """
  Deletes a bookmark.
  """
  def delete(conn, %{"id" => id}) do
    bookmark = Bookmarks.get_bookmark!(id)
    {:ok, _bookmark} = Bookmarks.delete_bookmark(bookmark)

    send_resp(conn, :no_content, "")
  end

  @doc """
  Checks if an entity is bookmarked.

  Query params:
  - type: bookmark_type
  - id: entity identifier (file path for files, UUID for others)
  """
  def check(conn, %{"type" => type, "id" => identifier}) do
    is_bookmarked = Bookmarks.check_if_bookmarked(type, identifier)
    bookmark = if is_bookmarked, do: Bookmarks.get_bookmark_by(type, identifier), else: nil

    json(conn, %{
      is_bookmarked: is_bookmarked,
      bookmark: if(bookmark, do: render_bookmark(bookmark), else: nil)
    })
  end

  # Private helpers

  defp add_opt(opts, _key, nil), do: opts
  defp add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp render_bookmarks(bookmarks) do
    Enum.map(bookmarks, &render_bookmark/1)
  end

  defp render_bookmark(%Bookmark{} = bookmark) do
    %{
      id: bookmark.id,
      bookmark_type: bookmark.bookmark_type,
      bookmark_id: bookmark.bookmark_id,
      file_path: bookmark.file_path,
      line_number: bookmark.line_number,
      url: bookmark.url,
      title: bookmark.title,
      description: bookmark.description,
      category: bookmark.category,
      priority: bookmark.priority,
      position: bookmark.position,
      project_id: bookmark.project_id,
      agent_id: bookmark.agent_id,
      accessed_at: bookmark.accessed_at,
      inserted_at: bookmark.inserted_at,
      updated_at: bookmark.updated_at
    }
  end

end
