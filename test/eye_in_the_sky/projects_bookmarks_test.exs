defmodule EyeInTheSky.ProjectsBookmarksTest do
  use EyeInTheSky.DataCase

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Projects.Project
  alias EyeInTheSky.Workspaces

  defp create_workspace do
    user = EyeInTheSky.Factory.user_fixture()
    Workspaces.default_workspace_for_user!(user)
  end

  defp create_project(name, workspace_id \\ nil) do
    attrs = %{
      name: name,
      path: "/tmp/#{name}-#{System.unique_integer([:positive])}"
    }

    attrs =
      case workspace_id do
        nil -> attrs
        workspace_id -> Map.put(attrs, :workspace_id, workspace_id)
      end

    {:ok, project} =
      Projects.create_project(attrs)

    project
  end

  describe "Project.changeset/2 with bookmarked" do
    test "casts bookmarked field" do
      project = create_project("test")
      changeset = Project.changeset(project, %{bookmarked: true})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :bookmarked) == true
    end
  end

  describe "set_bookmarked/2" do
    test "sets bookmarked to true" do
      project = create_project("alpha")
      assert {:ok, updated} = Projects.set_bookmarked(project.id, true)
      assert updated.bookmarked == true
    end

    test "sets bookmarked to false" do
      {:ok, project} =
        Projects.create_project(%{
          name: "beta",
          path: "/tmp/beta-#{System.unique_integer([:positive])}",
          bookmarked: true
        })

      assert {:ok, updated} = Projects.set_bookmarked(project.id, false)
      assert updated.bookmarked == false
    end

    test "returns error for unknown id" do
      assert {:error, :not_found} = Projects.set_bookmarked(999_999, true)
    end
  end

  describe "get_project_for_workspace/2" do
    test "returns a project in the requested workspace" do
      workspace = create_workspace()
      project = create_project("workspace", workspace.id)

      assert {:ok, found} = Projects.get_project_for_workspace(project.id, workspace.id)
      assert found.id == project.id
      assert found.workspace_id == workspace.id
    end

    test "treats foreign workspace projects as not found" do
      workspace = create_workspace()
      foreign_workspace = create_workspace()
      project = create_project("foreign", foreign_workspace.id)

      assert {:error, :not_found} = Projects.get_project_for_workspace(project.id, workspace.id)
    end

    test "treats missing projects as not found" do
      workspace = create_workspace()

      assert {:error, :not_found} =
               Projects.get_project_for_workspace(999_999, workspace.id)
    end

    test "accepts string ids for project and workspace lookups" do
      workspace = create_workspace()
      project = create_project("string-id", workspace.id)

      assert {:ok, found} = Projects.get_project_for_workspace("#{project.id}", workspace.id)
      assert found.id == project.id

      assert {:ok, found_again} =
               Projects.get_project_for_workspace(project.id, "#{workspace.id}")

      assert found_again.id == project.id
    end
  end

  describe "list_projects_for_sidebar/0" do
    test "returns bookmarked projects before non-bookmarked" do
      a = create_project("aardvark")
      b = create_project("zebra")
      {:ok, b} = Projects.set_bookmarked(b.id, true)

      ids = Projects.list_projects_for_sidebar() |> Enum.map(& &1.id)
      zebra_pos = Enum.find_index(ids, &(&1 == b.id))
      aardvark_pos = Enum.find_index(ids, &(&1 == a.id))

      assert zebra_pos < aardvark_pos
    end

    test "multiple bookmarked projects are name-sorted among themselves (case-insensitive)" do
      {:ok, c} =
        Projects.create_project(%{
          name: "Cucumber",
          path: "/tmp/c-#{System.unique_integer([:positive])}",
          bookmarked: true
        })

      {:ok, a} =
        Projects.create_project(%{
          name: "apple",
          path: "/tmp/a-#{System.unique_integer([:positive])}",
          bookmarked: true
        })

      {:ok, b} =
        Projects.create_project(%{
          name: "Banana",
          path: "/tmp/b-#{System.unique_integer([:positive])}",
          bookmarked: true
        })

      bookmarked_ids =
        Projects.list_projects_for_sidebar()
        |> Enum.filter(& &1.bookmarked)
        |> Enum.map(& &1.id)

      assert bookmarked_ids == [a.id, b.id, c.id]
    end

    test "unbookmarking a project moves it back below bookmarked ones" do
      move = create_project("move")
      {:ok, _} = Projects.set_bookmarked(move.id, true)
      {:ok, _} = Projects.set_bookmarked(move.id, false)

      result = Projects.list_projects_for_sidebar()
      assert Enum.find(result, &(&1.id == move.id)).bookmarked == false
    end

    test "inactive projects are excluded" do
      Projects.create_project(%{
        name: "hidden",
        path: "/tmp/h-#{System.unique_integer([:positive])}",
        active: false
      })

      _active = create_project("visible")

      names = Projects.list_projects_for_sidebar() |> Enum.map(& &1.name)
      refute "hidden" in names
      assert "visible" in names
    end
  end
end
