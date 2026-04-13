defmodule EyeInTheSky.BookmarksTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Bookmarks
  alias EyeInTheSky.Bookmarks.Bookmark

  defp create_bookmark(attrs) do
    {:ok, bookmark} = Bookmarks.create_bookmark(attrs)
    bookmark
  end

  describe "build_bookmark_query / check_if_bookmarked for url type" do
    test "returns false when no url bookmark exists for the url" do
      refute Bookmarks.check_if_bookmarked("url", "https://example.com")
    end

    test "returns true when a url bookmark exists for the url" do
      create_bookmark(%{bookmark_type: "url", url: "https://example.com", title: "Example"})
      assert Bookmarks.check_if_bookmarked("url", "https://example.com")
    end

    test "does not match a different url" do
      create_bookmark(%{bookmark_type: "url", url: "https://example.com", title: "Example"})
      refute Bookmarks.check_if_bookmarked("url", "https://other.com")
    end
  end

  describe "get_bookmark_by for url type" do
    test "returns {:error, :not_found} when no url bookmark exists" do
      assert {:error, :not_found} = Bookmarks.get_bookmark_by("url", "https://missing.com")
    end

    test "returns {:ok, bookmark} when url bookmark exists" do
      create_bookmark(%{bookmark_type: "url", url: "https://found.com", title: "Found"})
      assert {:ok, %Bookmark{bookmark_type: "url", url: "https://found.com"}} =
               Bookmarks.get_bookmark_by("url", "https://found.com")
    end
  end

  describe "build_bookmark_query returns nil for unknown type" do
    test "check_if_bookmarked returns false for unknown type" do
      refute Bookmarks.check_if_bookmarked("unknown", "anything")
    end

    test "get_bookmark_by returns :not_found for unknown type" do
      assert {:error, :not_found} = Bookmarks.get_bookmark_by("unknown", "anything")
    end
  end
end
