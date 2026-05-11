defmodule EyeInTheSkyWeb.WorkspaceLive.TasksTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "renders the workspace tasks page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/workspace/tasks")

      assert html =~ "Tasks"
    end

    test "renders coming soon placeholder", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/workspace/tasks")

      assert html =~ "coming soon"
    end
  end

  describe "render/1" do
    test "page title includes Tasks", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/workspace/tasks")

      assert html =~ "Tasks"
    end

    test "renders workspace content", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/workspace/tasks")

      assert is_binary(html) && byte_size(html) > 0
    end
  end
end
