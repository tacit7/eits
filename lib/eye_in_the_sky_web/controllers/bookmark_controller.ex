defmodule EyeInTheSkyWeb.BookmarkController do
  use EyeInTheSkyWeb, :controller

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.Bookmarks
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

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
      |> maybe_opt(:bookmark_type, params["type"])
      |> maybe_opt(:category, params["category"])
      |> maybe_opt(:project_id, parse_int(params["project_id"]))
      |> maybe_opt(:agent_id, params["agent_id"])
      |> maybe_opt(:limit, parse_int(params["limit"]))

    bookmarks = Bookmarks.list_bookmarks(opts)

    json(conn, %{bookmarks: Enum.map(bookmarks, &ApiPresenter.present_bookmark/1)})
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
          bookmark: ApiPresenter.present_bookmark(bookmark)
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

    json(conn, %{bookmark: ApiPresenter.present_bookmark(bookmark)})
  end

  @doc """
  Updates a bookmark.
  """
  def update(conn, %{"id" => id} = params) do
    bookmark = Bookmarks.get_bookmark!(id)

    case Bookmarks.update_bookmark(bookmark, params) do
      {:ok, bookmark} ->
        json(conn, %{bookmark: ApiPresenter.present_bookmark(bookmark)})

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
    bookmark =
      case Bookmarks.get_bookmark_by(type, identifier) do
        {:ok, b} -> b
        {:error, :not_found} -> nil
      end

    json(conn, %{
      is_bookmarked: is_bookmarked,
      bookmark: if(bookmark, do: ApiPresenter.present_bookmark(bookmark), else: nil)
    })
  end

end
