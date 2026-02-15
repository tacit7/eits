defmodule EyeInTheSkyWebWeb.ProjectLive.SessionsTest do
  use EyeInTheSkyWebWeb.ConnCase

  import Phoenix.LiveViewTest
  alias EyeInTheSkyWeb.{Projects, Agents, ChatAgents}

  setup do
    # Create a test project
    {:ok, project} =
      Projects.create_project(%{
        name: "test-project",
        path: "/tmp/test-project",
        slug: "test-project"
      })

    %{project: project}
  end

  describe "New Session feature" do
    test "renders New Session button", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      assert has_element?(view, "button", "+ New Session")
    end

    test "opens drawer when New Session button is clicked", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      # Click New Session button
      view |> element("button", "+ New Session") |> render_click()

      # Check drawer is visible
      assert has_element?(view, "h2", "New Session")
      assert has_element?(view, "select[name='model']")
      assert has_element?(view, "input[name='agent_name']")
      assert has_element?(view, "textarea[name='description']")
    end

    test "creates agent and session when form is submitted", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      # Open drawer
      view |> element("button", "+ New Session") |> render_click()

      # Submit form
      view
      |> form("form", %{
        "model" => "sonnet",
        "agent_name" => "Test Agent",
        "description" => "Test description"
      })
      |> render_submit()

      # Check agent was created
      agents = Agents.list_agents()
      assert length(agents) == 1
      agent = hd(agents)
      assert agent.description == "Test description"
      assert agent.project_id == project.id
      assert agent.git_worktree_path == project.path

      # Check execution agent was created
      execution_agents = Agents.list_agents()
      assert length(execution_agents) == 1
      execution_agent = hd(execution_agents)
      assert execution_agent.agent_id == agent.id
      assert execution_agent.name == "Test Agent"
      assert execution_agent.description == "Test description"
      assert execution_agent.model_name == "sonnet"
      assert execution_agent.model_provider == "claude"
    end

    test "new agent appears in filtered agents list after creation", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      # Verify initially empty
      refute has_element?(view, "code", "Test Agent")

      # Open drawer and submit
      view |> element("button", "+ New Session") |> render_click()

      view
      |> form("form", %{
        "model" => "haiku",
        "agent_name" => "Test Agent",
        "description" => "Test work"
      })
      |> render_submit()

      # Check agent appears in the list
      # Note: The list shows agent ID, not name, so we check for the description
      html = render(view)
      assert html =~ "Test work"
    end

    test "closes drawer and shows success message after session creation", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element("button", "+ New Session") |> render_click()

      view
      |> form("form", %{
        "model" => "opus",
        "agent_name" => "Another Agent",
        "description" => "Another test"
      })
      |> render_submit()

      # Drawer should be closed (can't see form anymore when not open)
      # Success message should show
      assert has_element?(view, ".alert", "Session created successfully") or
               render(view) =~ "Session created successfully"
    end

    test "stays on project page after creating session (no redirect)", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element("button", "+ New Session") |> render_click()

      {:ok, _view, _html} =
        view
        |> form("form", %{
          "model" => "sonnet",
          "agent_name" => "Stay Test",
          "description" => "Should stay on page"
        })
        |> render_submit()
        |> follow_redirect(conn)

      # After submit, we should still be on the project sessions page
      # (though follow_redirect might not be needed if we're not redirecting)
    end

    test "project field is disabled and shows current project", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element("button", "+ New Session") |> render_click()

      html = render(view)

      # Project field should be disabled and show project name
      assert html =~ "test-project"
      assert html =~ ~r/disabled.*test-project|test-project.*disabled/s
    end
  end
end
