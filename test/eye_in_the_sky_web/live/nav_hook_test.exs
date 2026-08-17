defmodule EyeInTheSkyWeb.NavHookTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{Factory, Projects, Workspaces}
  alias EyeInTheSkyWeb.NavHook

  defp build_socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, flash: %{}}, assigns),
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }
  end

  test "scopes palette projects to the current workspace" do
    user = Factory.user_fixture()
    workspace = Workspaces.default_workspace_for_user!(user)

    other_user = Factory.user_fixture()
    other_workspace = Workspaces.default_workspace_for_user!(other_user)

    {:ok, own_project} =
      Projects.create_project(%{
        name: "NavHook project #{Factory.uniq()}",
        path: "/tmp/navhook-project",
        slug: "navhook-project",
        workspace_id: workspace.id
      })

    {:ok, foreign_project} =
      Projects.create_project(%{
        name: "Foreign project #{Factory.uniq()}",
        path: "/tmp/navhook-foreign",
        slug: "navhook-foreign",
        workspace_id: other_workspace.id
      })

    {:cont, result} = NavHook.on_mount(:default, %{}, %{}, build_socket(%{current_user: user}))

    assert result.assigns.workspace_id == workspace.id
    assert Enum.any?(result.assigns.palette_projects, &(&1.id == own_project.id))
    refute Enum.any?(result.assigns.palette_projects, &(&1.id == foreign_project.id))
  end
end
