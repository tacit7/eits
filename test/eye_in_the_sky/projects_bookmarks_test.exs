defmodule EyeInTheSky.ProjectsBookmarksTest do
  use EyeInTheSky.DataCase

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Projects.Project

  defp create_project(name) do
    {:ok, project} =
      Projects.create_project(%{name: name, path: "/tmp/#{name}-#{System.unique_integer([:positive])}"})
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
end
