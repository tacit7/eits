defmodule EyeInTheSkyWeb.WorkspaceLive.NotesTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "renders the workspace notes page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/workspace/notes")

      assert html =~ "Notes"
    end

    test "renders coming soon placeholder", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/workspace/notes")

      assert html =~ "coming soon"
    end
  end

  describe "render/1" do
    test "page title includes Notes", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/workspace/notes")

      assert html =~ "Notes"
    end

    test "renders workspace content", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/workspace/notes")

      assert is_binary(html) && byte_size(html) > 0
    end
  end
end
