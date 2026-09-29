defmodule EyeInTheSkyWeb.Helpers.ProjectLiveHelpersTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.{Factory, Projects, Workspaces}
  alias EyeInTheSkyWeb.Helpers.ProjectLiveHelpers

  defp socket(assigns) do
    %Phoenix.LiveView.Socket{assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns)}
  end

  setup do
    user = Factory.user_fixture()
    workspace = Workspaces.default_workspace_for_user!(user)
    other_workspace = Workspaces.default_workspace_for_user!(Factory.user_fixture())

    projects =
      for ws <- [workspace, other_workspace] do
        {:ok, project} =
          Projects.create_project(%{
            name: "Scoped project #{Factory.uniq()}",
            workspace_id: ws.id
          })

        project
      end

    [own, foreign] = projects
    %{user: user, workspace: workspace, own: own, foreign: foreign}
  end

  test "resolves local projects using the user's workspace", %{user: user, own: own} do
    assert ProjectLiveHelpers.load_project_for_socket(socket(%{current_user: user}), own.id) ==
             own
  end

  test "foreign, missing, invalid and unscoped project lookups all return nil", context do
    scoped_socket = socket(%{workspace: context.workspace})

    for id <- [context.foreign.id, -1, nil, "invalid"] do
      assert ProjectLiveHelpers.load_project_for_socket(scoped_socket, id) == nil
    end

    assert ProjectLiveHelpers.load_project_for_socket(socket(%{}), context.own.id) == nil
  end

  test "mount stops before foreign projects can fall back to global scope", context do
    assert_raise Ecto.NoResultsError, fn ->
      ProjectLiveHelpers.mount_project(
        socket(%{workspace: context.workspace}),
        %{"id" => to_string(context.foreign.id)},
        sidebar_tab: :tasks,
        page_title_prefix: "Tasks"
      )
    end
  end

  test "valid project mount assigns only local active palette projects", context do
    {:ok, _inactive} =
      Projects.create_project(%{
        name: "Inactive #{Factory.uniq()}",
        workspace_id: context.workspace.id,
        active: false
      })

    result =
      ProjectLiveHelpers.mount_project(
        socket(%{workspace: context.workspace}),
        %{"id" => to_string(context.own.id)},
        sidebar_tab: :tasks,
        page_title_prefix: "Tasks"
      )

    assert result.assigns.project == context.own
    assert result.assigns.workspace_id == context.workspace.id
    assert result.assigns.palette_projects == [%{id: context.own.id, name: context.own.name}]
  end

  test "palette fails closed without workspace context" do
    assert ProjectLiveHelpers.palette_projects_for_socket(socket(%{})) == []
  end
end
