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

  describe "workspace isolation" do
    test "rejects a project outside the current workspace", %{conn: conn} do
      other_user = user_fixture()
      other_workspace = Workspaces.default_workspace_for_user!(other_user)
      foreign_project = create_project_in_workspace(other_workspace.id)

      {:ok, view, _html} = live(conn, ~p"/projects/#{foreign_project.id}")

      assert has_element?(view, "#flash-error", "Project not found")
    end

    test "shared project mounts reject foreign and missing projects before loading page data", %{
      conn: conn
    } do
      other_workspace = Workspaces.default_workspace_for_user!(user_fixture())
      foreign_project = create_project_in_workspace(other_workspace.id)

      for section <- ~w(kanban notes agents skills teams jobs prompts),
          project_id <- [foreign_project.id, -1] do
        assert_raise Ecto.NoResultsError, fn ->
          live(conn, "/projects/#{project_id}/#{section}")
        end
      end

      for project_id <- [foreign_project.id, -1] do
        assert {:error, {:redirect, %{to: "/sessions", flash: %{"error" => "Project not found"}}}} =
                 live(conn, "/projects/#{project_id}/sessions")
      end

      for project_id <- [foreign_project.id, -1] do
        assert {:error,
                {:redirect, %{to: "/workspace/tasks", flash: %{"error" => "Project not found"}}}} =
                 live(conn, "/projects/#{project_id}/tasks")
      end
    end
  end
end
