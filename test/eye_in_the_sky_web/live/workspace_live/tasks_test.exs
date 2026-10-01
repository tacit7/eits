defmodule EyeInTheSkyWeb.WorkspaceLive.TasksTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "renders the short tasks route when auth bypass has no session user", %{conn: _conn} do
      previous = Application.get_env(:eye_in_the_sky, :disable_auth, false)
      Application.put_env(:eye_in_the_sky, :disable_auth, true)
      on_exit(fn -> Application.put_env(:eye_in_the_sky, :disable_auth, previous) end)

      _user = EyeInTheSky.Factory.user_fixture()
      conn = Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})

      {:ok, _lv, html} = live(conn, ~p"/tasks")

      assert html =~ "Tasks"
    end

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

      assert html =~ "Workspace tasks view | coming soon."
    end
  end
end
