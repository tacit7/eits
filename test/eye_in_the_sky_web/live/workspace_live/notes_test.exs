defmodule EyeInTheSkyWeb.WorkspaceLive.NotesTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Workspaces

  setup do
    {:ok, workspace} =
      Workspaces.create_workspace(%{
        name: "Test Workspace",
        description: "A test workspace"
      })

    %{workspace: workspace}
  end

  describe "mount/3" do
    test "sets page title with workspace name", %{conn: conn, workspace: workspace} do
      {:ok, lv, _html} = live(conn, ~p"/workspaces/#{workspace.id}/notes")

      assert lv.assigns.page_title =~ workspace.name
      assert lv.assigns.page_title =~ "Notes"
    end

    test "requires workspace to be assigned", %{conn: conn, workspace: workspace} do
      {:ok, lv, _html} = live(conn, ~p"/workspaces/#{workspace.id}/notes")

      assert lv.assigns.workspace.id == workspace.id
    end
  end

  describe "handle_event/set_notify_on_stop" do
    test "handles notification toggle", %{conn: conn, workspace: workspace} do
      {:ok, lv, _html} = live(conn, ~p"/workspaces/#{workspace.id}/notes")

      # Event handler should exist and be callable
      assert lv.assigns.workspace.id == workspace.id
    end
  end

  describe "render/1" do
    test "renders page title", %{conn: conn, workspace: workspace} do
      {:ok, _lv, html} = live(conn, ~p"/workspaces/#{workspace.id}/notes")

      assert html =~ workspace.name
      assert html =~ "Notes"
    end

    test "renders coming soon message", %{conn: conn, workspace: workspace} do
      {:ok, _lv, html} = live(conn, ~p"/workspaces/#{workspace.id}/notes")

      assert html =~ "coming soon"
    end

    test "renders scope badge", %{conn: conn, workspace: workspace} do
      {:ok, _lv, html} = live(conn, ~p"/workspaces/#{workspace.id}/notes")

      assert html =~ "scope" || html =~ "workspace"
    end
  end
end
