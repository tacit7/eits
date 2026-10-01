defmodule EyeInTheSkyWeb.Components.Rail.RailStateActionsTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.{Factory, Projects, Workspaces}
  alias EyeInTheSkyWeb.Components.Rail.ProjectActions

  defp build_socket(assigns) do
    base = %{
      __changed__: %{},
      flash: %{},
      flyout_sessions: [],
      flyout_channels: [],
      flyout_tasks: [],
      flyout_notes: [],
      flyout_skills: [],
      flyout_prompts: [],
      flyout_jobs: [],
      flyout_file_nodes: [],
      flyout_file_expanded: MapSet.new(),
      flyout_file_children: %{},
      flyout_file_error: nil,
      flyout_usage: nil,
      sidebar_project: nil,
      workspace: nil,
      workspace_id: nil,
      session_sort: :last_activity,
      session_name_filter: "",
      session_show: :twenty,
      task_state_filter: nil,
      active_section: :sessions,
      flyout_open: true
    }

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base, assigns),
      private: %{live_temp: %{}}
    }
  end

  defp project_attrs(name, workspace_id) do
    n = Factory.uniq()

    %{
      name: "#{name} #{n}",
      path: "/tmp/#{String.downcase(name)}-#{n}",
      slug: "#{String.downcase(name)}-#{n}",
      workspace_id: workspace_id
    }
  end

  test "handle_restore_project/2 keeps the current workspace project when the saved project is foreign" do
    user = Factory.user_fixture()
    workspace = Workspaces.default_workspace_for_user!(user)

    other_user = Factory.user_fixture()
    other_workspace = Workspaces.default_workspace_for_user!(other_user)

    {:ok, current_project} = Projects.create_project(project_attrs("Current", workspace.id))
    {:ok, foreign_project} = Projects.create_project(project_attrs("Foreign", other_workspace.id))

    socket =
      build_socket(%{
        sidebar_project: current_project,
        workspace: workspace,
        workspace_id: workspace.id
      })

    {:noreply, result} =
      ProjectActions.handle_restore_project(to_string(foreign_project.id), socket)

    assert result.assigns.sidebar_project.id == current_project.id
    assert result.assigns.workspace_id == workspace.id
    assert Enum.any?(result.assigns.projects, &(&1.id == current_project.id))
    assert Enum.any?(result.assigns.projects, &(&1.id == foreign_project.id))
  end

  test "handle_restore_project/2 falls back to a valid workspace project when no project is selected" do
    user = Factory.user_fixture()
    workspace = Workspaces.default_workspace_for_user!(user)

    other_user = Factory.user_fixture()
    other_workspace = Workspaces.default_workspace_for_user!(other_user)

    {:ok, fallback_project} = Projects.create_project(project_attrs("Fallback", workspace.id))
    {:ok, foreign_project} = Projects.create_project(project_attrs("Foreign", other_workspace.id))

    socket =
      build_socket(%{
        workspace: workspace,
        workspace_id: workspace.id
      })

    {:noreply, result} =
      ProjectActions.handle_restore_project(to_string(foreign_project.id), socket)

    assert result.assigns.sidebar_project.id == fallback_project.id
    assert result.assigns.workspace_id == workspace.id
    assert Enum.any?(result.assigns.projects, &(&1.id == fallback_project.id))
    assert Enum.any?(result.assigns.projects, &(&1.id == foreign_project.id))
  end
end
