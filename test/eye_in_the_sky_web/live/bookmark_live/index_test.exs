defmodule EyeInTheSkyWeb.BookmarkLive.IndexTest do
  use EyeInTheSkyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import EyeInTheSky.Factory

  alias EyeInTheSky.Bookmarks

  # ------------------------------------------------------------------ mount --

  describe "mount" do
    test "renders the bookmarks page with title", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ "Bookmarks"
    end

    test "shows empty state when no bookmarks exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ "No bookmarks yet"
    end

    test "renders type filter dropdown", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ "All Types"
      assert html =~ ~s(phx-change="filter_type")
    end

    test "renders category filter dropdown", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ "All Categories"
      assert html =~ ~s(phx-change="filter_category")
    end

    test "lists existing bookmarks on mount", %{conn: conn} do
      bookmark = bookmark_fixture(%{title: "My Unique Title"})
      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ bookmark.title
    end
  end

  # --------------------------------------------------------------- rendering --

  describe "bookmark card rendering" do
    test "shows bookmark type badge", %{conn: conn} do
      bookmark_fixture(%{bookmark_type: "note", bookmark_id: "n1", title: "Note bookmark"})
      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ "note"
    end

    test "shows category badge when category is set", %{conn: conn} do
      bookmark_fixture(%{
        bookmark_type: "note",
        bookmark_id: "n2",
        title: "Cat bookmark",
        category: "important"
      })

      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ "important"
    end

    test "shows priority badge when priority > 0", %{conn: conn} do
      bookmark_fixture(%{
        bookmark_type: "note",
        bookmark_id: "n3",
        title: "Prio bookmark",
        priority: 2
      })

      {:ok, lv, _html} = live(conn, ~p"/bookmarks")
      assert has_element?(lv, ".badge-warning", "P2")
    end

    test "does not show priority badge when priority is 0", %{conn: conn} do
      bookmark_fixture(%{bookmark_type: "note", bookmark_id: "n4", title: "No prio", priority: 0})
      {:ok, lv, _html} = live(conn, ~p"/bookmarks")
      # Use element selector — plain string match hits session tokens / hashes
      refute has_element?(lv, ".badge-warning", "P0")
    end

    test "shows description when present", %{conn: conn} do
      bookmark_fixture(%{
        bookmark_type: "note",
        bookmark_id: "n5",
        title: "Desc bookmark",
        description: "A helpful description"
      })

      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ "A helpful description"
    end

    test "shows file path for file bookmark", %{conn: conn} do
      bookmark_fixture(%{
        bookmark_type: "file",
        file_path: "/some/path/to/file.ex",
        title: "File bookmark"
      })

      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ "/some/path/to/file.ex"
    end

    test "shows url for url bookmark", %{conn: conn} do
      bookmark_fixture(%{
        bookmark_type: "url",
        url: "https://example.com",
        title: "URL bookmark"
      })

      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ "https://example.com"
    end

    test "renders delete button for each bookmark", %{conn: conn} do
      bookmark = bookmark_fixture(%{title: "Delete me"})
      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ ~s(phx-value-id="#{bookmark.id}")
    end

    test "each bookmark has a stable DOM id", %{conn: conn} do
      bookmark = bookmark_fixture(%{title: "Stable ID"})
      {:ok, _lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ ~s(id="bookmark-#{bookmark.id}")
    end
  end

  # ------------------------------------------------------------------ filter --

  describe "filter_type event" do
    test "filters bookmarks by type", %{conn: conn} do
      file_bm = bookmark_fixture(%{bookmark_type: "file", file_path: "/f.ex", title: "File one"})
      note_bm = bookmark_fixture(%{bookmark_type: "note", bookmark_id: "n1", title: "Note one"})

      {:ok, lv, _html} = live(conn, ~p"/bookmarks")

      html =
        lv
        |> element(~s(select[phx-change="filter_type"]))
        |> render_change(%{"type" => "file"})

      assert html =~ file_bm.title
      refute html =~ note_bm.title
    end

    test "clearing type filter shows all bookmarks", %{conn: conn} do
      file_bm = bookmark_fixture(%{bookmark_type: "file", file_path: "/g.ex", title: "File two"})
      note_bm = bookmark_fixture(%{bookmark_type: "note", bookmark_id: "n2", title: "Note two"})

      {:ok, lv, _html} = live(conn, ~p"/bookmarks")

      # First narrow to file, then clear
      lv
      |> element(~s(select[phx-change="filter_type"]))
      |> render_change(%{"type" => "file"})

      html =
        lv
        |> element(~s(select[phx-change="filter_type"]))
        |> render_change(%{"type" => ""})

      assert html =~ file_bm.title
      assert html =~ note_bm.title
    end
  end

  describe "filter_category event" do
    test "filters bookmarks by category", %{conn: conn} do
      important = bookmark_fixture(%{bookmark_type: "note", bookmark_id: "imp1", title: "Important one", category: "important"})
      idea = bookmark_fixture(%{bookmark_type: "note", bookmark_id: "idea1", title: "Idea one", category: "ideas"})

      {:ok, lv, _html} = live(conn, ~p"/bookmarks")

      html =
        lv
        |> element(~s(select[phx-change="filter_category"]))
        |> render_change(%{"category" => "important"})

      assert html =~ important.title
      refute html =~ idea.title
    end

    test "clearing category filter shows all bookmarks", %{conn: conn} do
      important = bookmark_fixture(%{bookmark_type: "note", bookmark_id: "imp2", title: "Imp two", category: "important"})
      idea = bookmark_fixture(%{bookmark_type: "note", bookmark_id: "idea2", title: "Idea two", category: "ideas"})

      {:ok, lv, _html} = live(conn, ~p"/bookmarks")

      lv
      |> element(~s(select[phx-change="filter_category"]))
      |> render_change(%{"category" => "important"})

      html =
        lv
        |> element(~s(select[phx-change="filter_category"]))
        |> render_change(%{"category" => ""})

      assert html =~ important.title
      assert html =~ idea.title
    end
  end

  # ------------------------------------------------------------------ delete --

  describe "delete event" do
    test "removes a bookmark from the list", %{conn: conn} do
      bookmark = bookmark_fixture(%{title: "To be deleted"})
      {:ok, lv, html} = live(conn, ~p"/bookmarks")

      assert html =~ bookmark.title

      html =
        lv
        |> element(~s(button[phx-click="delete"][phx-value-id="#{bookmark.id}"]))
        |> render_click()

      refute html =~ bookmark.title
    end

    test "shows flash error when bookmark not found", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/bookmarks")
      html = render_click(lv, "delete", %{"id" => 9_999_999})
      assert html =~ "Bookmark not found"
    end

    test "bookmark is removed from the database after delete", %{conn: conn} do
      bookmark = bookmark_fixture(%{title: "DB delete check"})
      {:ok, lv, _html} = live(conn, ~p"/bookmarks")

      lv
      |> element(~s(button[phx-click="delete"][phx-value-id="#{bookmark.id}"]))
      |> render_click()

      assert Bookmarks.get_bookmark(bookmark.id) == nil
    end
  end

  # ------------------------------------------------------- PubSub live updates --

  describe "PubSub live updates" do
    test "adds a new bookmark when bookmark_created is broadcast", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/bookmarks")

      {:ok, bookmark} =
        Bookmarks.create_bookmark(%{
          bookmark_type: "note",
          bookmark_id: "pubsub-1",
          title: "PubSub created"
        })

      html = render(lv)
      assert html =~ bookmark.title
    end

    test "removes a bookmark when bookmark_deleted is broadcast", %{conn: conn} do
      bookmark = bookmark_fixture(%{title: "PubSub will delete"})
      {:ok, lv, html} = live(conn, ~p"/bookmarks")
      assert html =~ bookmark.title

      Bookmarks.delete_bookmark(bookmark)

      html = render(lv)
      refute html =~ "PubSub will delete"
    end
  end
end
