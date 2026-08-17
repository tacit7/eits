defmodule EyeInTheSkyWeb.ProjectLive.ShowTest do
  use EyeInTheSkyWeb.ConnCase

  import Phoenix.LiveViewTest
  import EyeInTheSky.Factory

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Workspaces

  defp create_project_in_workspace(workspace_id) do
    n = System.unique_integer([:positive])

    {:ok, project} =
      Projects.create_project(%{
        name: "Show Project #{n}",
        slug: "show-project-#{n}",
        path: "/tmp/show-project-#{n}",
        workspace_id: workspace_id
      })

    project
  end

  describe "cross-project access guard" do
    test "rejects a project outside the current workspace", %{conn: conn} do
      other_user = user_fixture()
      other_workspace = Workspaces.default_workspace_for_user!(other_user)
      foreign_project = create_project_in_workspace(other_workspace.id)

      {:ok, view, _html} = live(conn, ~p"/projects/#{foreign_project.id}")

      assert has_element?(view, "#flash-error", "Project not found")
    end
  end
end
