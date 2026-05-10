defmodule EyeInTheSkyWeb.BookmarkControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Bookmarks

  import EyeInTheSky.Factory

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_bookmark(overrides \\ %{}) do
    base = %{
      "bookmark_type" => "url",
      "url" => "https://example.com/#{uniq()}",
      "title" => "Test bookmark #{uniq()}"
    }

    {:ok, bookmark} = Bookmarks.create_bookmark(Map.merge(base, overrides))
    bookmark
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/bookmarks
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/bookmarks" do
    test "returns empty list when no bookmarks exist", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/bookmarks")
      resp = json_response(conn, 200)

      assert is_list(resp["bookmarks"])
    end

    test "returns existing bookmarks", %{conn: conn} do
      bookmark = create_bookmark()
      conn = get(conn, ~p"/api/v1/bookmarks")
      resp = json_response(conn, 200)

      ids = Enum.map(resp["bookmarks"], & &1["id"])
      assert bookmark.id in ids
    end

    test "filters by type param", %{conn: conn} do
      create_bookmark(%{"bookmark_type" => "url", "url" => "https://url-type.com/#{uniq()}"})

      {:ok, file_bm} =
        Bookmarks.create_bookmark(%{
          "bookmark_type" => "file",
          "file_path" => "/tmp/test_#{uniq()}.ex"
        })

      conn = get(conn, ~p"/api/v1/bookmarks?type=file")
      resp = json_response(conn, 200)

      types = Enum.map(resp["bookmarks"], & &1["bookmark_type"])
      assert Enum.all?(types, &(&1 == "file"))
      assert Enum.any?(resp["bookmarks"], &(&1["id"] == file_bm.id))
    end

    test "filters by category param", %{conn: conn} do
      create_bookmark(%{"category" => "work"})
      create_bookmark(%{"category" => "personal"})

      conn = get(conn, ~p"/api/v1/bookmarks?category=work")
      resp = json_response(conn, 200)

      categories = Enum.map(resp["bookmarks"], & &1["category"])
      assert Enum.all?(categories, &(&1 == "work"))
    end

    test "respects limit param", %{conn: conn} do
      for _ <- 1..5, do: create_bookmark()

      conn = get(conn, ~p"/api/v1/bookmarks?limit=2")
      resp = json_response(conn, 200)

      assert length(resp["bookmarks"]) <= 2
    end

    test "filters by project_id param", %{conn: conn} do
      project = project_fixture()
      create_bookmark(%{"project_id" => project.id})
      create_bookmark()

      conn = get(conn, ~p"/api/v1/bookmarks?project_id=#{project.id}")
      resp = json_response(conn, 200)

      project_ids = Enum.map(resp["bookmarks"], & &1["project_id"])
      assert Enum.all?(project_ids, &(&1 == project.id))
    end

    test "filters by agent_id param", %{conn: conn} do
      agent = create_agent()
      create_bookmark(%{"agent_id" => agent.id})
      create_bookmark()

      conn = get(conn, ~p"/api/v1/bookmarks?agent_id=#{agent.id}")
      resp = json_response(conn, 200)

      agent_ids = Enum.map(resp["bookmarks"], & &1["agent_id"])
      assert Enum.all?(agent_ids, &(&1 == agent.id))
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/bookmarks/:id
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/bookmarks/:id" do
    test "returns the bookmark and updates accessed_at", %{conn: conn} do
      bookmark = create_bookmark(%{"title" => "My URL Bookmark"})
      conn = get(conn, ~p"/api/v1/bookmarks/#{bookmark.id}")
      resp = json_response(conn, 200)

      assert resp["bookmark"]["id"] == bookmark.id
      assert resp["bookmark"]["title"] == "My URL Bookmark"
      assert resp["bookmark"]["bookmark_type"] == "url"
    end

    test "raises on unknown id", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        get(conn, ~p"/api/v1/bookmarks/9999999")
      end
    end

    test "touched bookmark has non-nil accessed_at after show", %{conn: conn} do
      bookmark = create_bookmark()
      assert is_nil(bookmark.accessed_at)

      get(conn, ~p"/api/v1/bookmarks/#{bookmark.id}")

      updated = Bookmarks.get_bookmark!(bookmark.id)
      refute is_nil(updated.accessed_at)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /api/v1/bookmarks
  # ---------------------------------------------------------------------------

  describe "POST /api/v1/bookmarks" do
    test "creates a url bookmark with valid params", %{conn: conn} do
      url = "https://example.com/#{uniq()}"

      conn =
        post(conn, ~p"/api/v1/bookmarks", %{
          "bookmark_type" => "url",
          "url" => url,
          "title" => "Example"
        })

      resp = json_response(conn, 201)

      assert resp["bookmark"]["bookmark_type"] == "url"
      assert resp["bookmark"]["url"] == url
      assert resp["bookmark"]["title"] == "Example"
      assert is_integer(resp["id"])
    end

    test "creates a file bookmark", %{conn: conn} do
      path = "/tmp/myfile_#{uniq()}.ex"

      conn =
        post(conn, ~p"/api/v1/bookmarks", %{
          "bookmark_type" => "file",
          "file_path" => path
        })

      resp = json_response(conn, 201)

      assert resp["bookmark"]["bookmark_type"] == "file"
      assert resp["bookmark"]["file_path"] == path
    end

    test "creates a note bookmark", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/bookmarks", %{
          "bookmark_type" => "note",
          "bookmark_id" => "note-uuid-#{uniq()}"
        })

      resp = json_response(conn, 201)
      assert resp["bookmark"]["bookmark_type"] == "note"
    end

    test "returns 422 when bookmark_type is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/bookmarks", %{"title" => "no type"})
      resp = json_response(conn, 422)

      assert resp["errors"]["bookmark_type"] != nil
    end

    test "returns 422 for invalid bookmark_type", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/bookmarks", %{
          "bookmark_type" => "invalid_type",
          "title" => "Bad type"
        })

      resp = json_response(conn, 422)
      assert resp["errors"]["bookmark_type"] != nil
    end

    test "returns 422 when url bookmark is missing url field", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/bookmarks", %{
          "bookmark_type" => "url",
          "title" => "missing url"
        })

      resp = json_response(conn, 422)
      assert resp["errors"]["url"] != nil
    end

    test "returns 422 when file bookmark is missing file_path", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/bookmarks", %{
          "bookmark_type" => "file",
          "title" => "no path"
        })

      resp = json_response(conn, 422)
      assert resp["errors"]["file_path"] != nil
    end

    test "returns 422 when note bookmark is missing bookmark_id", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/bookmarks", %{
          "bookmark_type" => "note",
          "title" => "no id"
        })

      resp = json_response(conn, 422)
      assert resp["errors"]["bookmark_id"] != nil
    end

    test "creates bookmark with optional priority and category", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/bookmarks", %{
          "bookmark_type" => "url",
          "url" => "https://priority-test.com/#{uniq()}",
          "priority" => 5,
          "category" => "research"
        })

      resp = json_response(conn, 201)

      assert resp["bookmark"]["priority"] == 5
      assert resp["bookmark"]["category"] == "research"
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH /api/v1/bookmarks/:id
  # ---------------------------------------------------------------------------

  describe "PATCH /api/v1/bookmarks/:id" do
    test "updates the title", %{conn: conn} do
      bookmark = create_bookmark(%{"title" => "Old title"})

      conn =
        patch(conn, ~p"/api/v1/bookmarks/#{bookmark.id}", %{"title" => "New title"})

      resp = json_response(conn, 200)
      assert resp["bookmark"]["title"] == "New title"
    end

    test "updates priority", %{conn: conn} do
      bookmark = create_bookmark()

      conn = patch(conn, ~p"/api/v1/bookmarks/#{bookmark.id}", %{"priority" => 10})
      resp = json_response(conn, 200)

      assert resp["bookmark"]["priority"] == 10
    end

    test "updates category", %{conn: conn} do
      bookmark = create_bookmark()

      conn = patch(conn, ~p"/api/v1/bookmarks/#{bookmark.id}", %{"category" => "starred"})
      resp = json_response(conn, 200)

      assert resp["bookmark"]["category"] == "starred"
    end

    test "returns 422 for invalid bookmark_type change", %{conn: conn} do
      bookmark = create_bookmark()

      conn =
        patch(conn, ~p"/api/v1/bookmarks/#{bookmark.id}", %{"bookmark_type" => "not_valid"})

      resp = json_response(conn, 422)
      assert resp["errors"]["bookmark_type"] != nil
    end

    test "raises on unknown id", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        patch(conn, ~p"/api/v1/bookmarks/9999999", %{"title" => "x"})
      end
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE /api/v1/bookmarks/:id
  # ---------------------------------------------------------------------------

  describe "DELETE /api/v1/bookmarks/:id" do
    test "deletes the bookmark and returns 204", %{conn: conn} do
      bookmark = create_bookmark()

      conn = delete(conn, ~p"/api/v1/bookmarks/#{bookmark.id}")
      assert response(conn, 204) == ""
    end

    test "bookmark is gone after deletion", %{conn: conn} do
      bookmark = create_bookmark()
      delete(conn, ~p"/api/v1/bookmarks/#{bookmark.id}")

      assert is_nil(Bookmarks.get_bookmark(bookmark.id))
    end

    test "raises on unknown id", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        delete(conn, ~p"/api/v1/bookmarks/9999999")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET /api/v1/bookmarks/check
  # ---------------------------------------------------------------------------

  describe "GET /api/v1/bookmarks/check" do
    test "returns is_bookmarked true when url bookmark exists", %{conn: conn} do
      url = "https://check-test.com/#{uniq()}"
      create_bookmark(%{"bookmark_type" => "url", "url" => url})

      conn = get(conn, ~p"/api/v1/bookmarks/check?type=url&id=#{url}")
      resp = json_response(conn, 200)

      assert resp["is_bookmarked"] == true
      assert resp["bookmark"] != nil
      assert resp["bookmark"]["url"] == url
    end

    test "returns is_bookmarked false when no bookmark exists for url", %{conn: conn} do
      url = "https://no-bookmark.com/#{uniq()}"

      conn = get(conn, ~p"/api/v1/bookmarks/check?type=url&id=#{url}")
      resp = json_response(conn, 200)

      assert resp["is_bookmarked"] == false
      assert is_nil(resp["bookmark"])
    end

    test "returns is_bookmarked true for file bookmark", %{conn: conn} do
      path = "/tmp/check_test_#{uniq()}.ex"
      {:ok, _} = Bookmarks.create_bookmark(%{"bookmark_type" => "file", "file_path" => path})

      conn = get(conn, ~p"/api/v1/bookmarks/check?type=file&id=#{path}")
      resp = json_response(conn, 200)

      assert resp["is_bookmarked"] == true
    end

    test "returns is_bookmarked true for note bookmark", %{conn: conn} do
      bm_id = "note-uuid-#{uniq()}"

      {:ok, _} =
        Bookmarks.create_bookmark(%{"bookmark_type" => "note", "bookmark_id" => bm_id})

      conn = get(conn, ~p"/api/v1/bookmarks/check?type=note&id=#{bm_id}")
      resp = json_response(conn, 200)

      assert resp["is_bookmarked"] == true
    end

    test "returns is_bookmarked false for unknown type", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/bookmarks/check?type=unknown&id=anything")
      resp = json_response(conn, 200)

      assert resp["is_bookmarked"] == false
      assert is_nil(resp["bookmark"])
    end
  end
end
