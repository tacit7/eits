defmodule EyeInTheSkyWeb.WorkspaceLive.NotesTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Accounts, Workspaces}

  setup do
    {:ok, user} = Accounts.get_or_create_user("workspace_notes_test_user")

    {:ok, workspace} =
      Workspaces.create_workspace(%{
        name: "Test Workspace",
        owner_user_id: user.id
      })

    %{workspace: workspace}
  end

  describe "mount/3" do
    test "renders the workspace notes page", %{conn: conn, workspace: workspace} do
      {:ok, _lv, html} = live(conn, ~p"/workspaces/#{workspace.id}/notes")

      assert html =~ workspace.name
      assert html =~ "Notes"
    end

    test "renders coming soon placeholder", %{conn: conn, workspace: workspace} do
      {:ok, _lv, html} = live(conn, ~p"/workspaces/#{workspace.id}/notes")

      assert html =~ "coming soon"
    end
  end

  describe "render/1" do
    test "page title includes workspace name and Notes", %{conn: conn, workspace: workspace} do
      {:ok, _lv, html} = live(conn, ~p"/workspaces/#{workspace.id}/notes")

      assert html =~ workspace.name
      assert html =~ "Notes"
    end

    test "renders workspace content", %{conn: conn, workspace: workspace} do
      {:ok, _lv, html} = live(conn, ~p"/workspaces/#{workspace.id}/notes")

      assert is_binary(html) && byte_size(html) > 0
    end
  end
end
