defmodule EyeInTheSkyWeb.WorkspaceLive.SessionsTest do
  use EyeInTheSkyWeb.ConnCase

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Factory, Projects, Workspaces}

  setup %{user: user} do
    workspace = Workspaces.default_workspace_for_user!(user)

    n = Factory.uniq()

    {:ok, project} =
      Projects.create_project(%{
        name: "WS Project #{n}",
        path: "/tmp/ws_project_#{n}",
        slug: "ws-project-#{n}",
        workspace_id: workspace.id
      })

    %{workspace: workspace, project: project}
  end

  describe "workspace sessions page" do
    test "renders page with New Agent button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspace/sessions")

      assert has_element?(view, "button", "New Agent")
    end

    test "renders scope badge", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/workspace/sessions")

      assert html =~ "Across all projects"
    end

    test "opens new session modal when New Agent is clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspace/sessions")

      view |> element("button", "New Agent") |> render_click()

      assert has_element?(view, "select[name='project_id']")
    end
  end

  describe "create_new_session — workspace project validation" do
    test "project dropdown only contains workspace-scoped projects", %{
      conn: conn,
      project: project
    } do
      # Create a project in a separate workspace (different user)
      other_user = Factory.user_fixture()
      other_workspace = Workspaces.default_workspace_for_user!(other_user)
      n = Factory.uniq()

      {:ok, other_project} =
        Projects.create_project(%{
          name: "Other WS Project #{n}",
          path: "/tmp/other_project_#{n}",
          slug: "other-project-#{n}",
          workspace_id: other_workspace.id
        })

      {:ok, view, _html} = live(conn, ~p"/workspace/sessions")

      view |> element("button", "New Agent") |> render_click()

      html = render(view)

      # Own workspace project IS in the dropdown
      assert html =~ "value=\"#{project.id}\""
      # Other workspace project is NOT in the dropdown
      refute html =~ "value=\"#{other_project.id}\""
    end

    test "server rejects project_id from another workspace via Actions directly", %{
      user: user,
      workspace: workspace,
      project: _project
    } do
      # Create a project in a separate workspace
      other_user = Factory.user_fixture()
      other_workspace = Workspaces.default_workspace_for_user!(other_user)
      n = Factory.uniq()

      {:ok, other_project} =
        Projects.create_project(%{
          name: "Other WS Project #{n}",
          path: "/tmp/other_project_#{n}",
          slug: "other-project-#{n}",
          workspace_id: other_workspace.id
        })

      socket =
        Phoenix.ConnTest.build_conn()
        |> Map.put(:assigns, %{workspace: workspace, current_user: user})
        |> then(fn _conn ->
          %Phoenix.LiveView.Socket{
            assigns: %{__changed__: %{}, flash: %{}, workspace: workspace, current_user: user}
          }
        end)

      params = %{
        "project_id" => to_string(other_project.id),
        "model" => "claude-sonnet-4-6",
        "description" => "Injection attempt"
      }

      {:noreply, result_socket} =
        EyeInTheSkyWeb.WorkspaceLive.Sessions.Actions.create_new_session(params, socket)

      assert result_socket.assigns.flash["error"] == "Project not found"
    end
  end
end
