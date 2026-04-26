defmodule EyeInTheSkyWeb.WorkspaceLive.SessionsTest do
  use EyeInTheSkyWeb.ConnCase

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Factory, Projects, Workspaces}
  alias EyeInTheSkyWeb.Components.NewSessionModal

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

  describe "NewSessionModal project_changed — cross-workspace agent scan guard" do
    test "project_changed with out-of-scope project_id returns empty agents", %{
      project: allowed_project
    } do
      # Build a component socket with only the allowed project in assigns
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          projects: [allowed_project],
          current_project: nil,
          available_agents: [],
          selected_model: "claude-sonnet-4-6",
          selected_provider: "claude",
          selected_prompt_id: nil,
          prefill_text: "",
          file_uploads: nil,
          show: true
        }
      }

      # Create an out-of-scope project in another workspace
      other_user = Factory.user_fixture()
      other_workspace = Workspaces.default_workspace_for_user!(other_user)
      n = Factory.uniq()

      {:ok, other_project} =
        Projects.create_project(%{
          name: "Foreign Project #{n}",
          path: "/tmp/foreign_project_#{n}",
          slug: "foreign-project-#{n}",
          workspace_id: other_workspace.id
        })

      {:noreply, result_socket} =
        NewSessionModal.handle_event(
          "project_changed",
          %{"project_id" => to_string(other_project.id)},
          socket
        )

      # The guard fired — project_path was set to nil, so the result equals a nil-path scan
      # (global agents only, NOT agents from the foreign project's filesystem path)
      {:noreply, nil_path_socket} =
        NewSessionModal.handle_event("project_changed", %{"project_id" => ""}, socket)

      assert result_socket.assigns.available_agents == nil_path_socket.assigns.available_agents
    end

    test "project_changed with allowed project_id proceeds normally", %{
      project: allowed_project
    } do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          projects: [allowed_project],
          current_project: nil,
          available_agents: [],
          selected_model: "claude-sonnet-4-6",
          selected_provider: "claude",
          selected_prompt_id: nil,
          prefill_text: "",
          file_uploads: nil,
          show: true
        }
      }

      {:noreply, result_socket} =
        NewSessionModal.handle_event(
          "project_changed",
          %{"project_id" => to_string(allowed_project.id)},
          socket
        )

      # Returns noreply without crashing (agents list is a list, possibly empty if no .claude dir)
      assert is_list(result_socket.assigns.available_agents)
    end
  end
end
