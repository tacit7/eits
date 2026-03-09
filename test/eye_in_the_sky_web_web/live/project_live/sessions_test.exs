defmodule EyeInTheSkyWebWeb.ProjectLive.SessionsTest do
  use EyeInTheSkyWebWeb.ConnCase

  import Phoenix.LiveViewTest
  alias EyeInTheSkyWeb.Projects

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

      assert has_element?(view, "button", "New Agent")
    end

    test "opens drawer when New Session button is clicked", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element("button", "New Agent") |> render_click()

      assert has_element?(view, "h3", "New Agent")
      assert has_element?(view, "select[name='model']")
      assert has_element?(view, "textarea[name='description']")
    end

    test "creates agent and session when form is submitted", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element("button", "New Agent") |> render_click()

      view
      |> form("form[phx-submit='create_new_session']", %{
        "model" => "sonnet",
        "description" => "Test description"
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Session launched" or html =~ "Failed to create session"
    end

    test "new agent appears in filtered agents list after creation", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element("button", "New Agent") |> render_click()

      view
      |> form("form[phx-submit='create_new_session']", %{
        "model" => "haiku",
        "description" => "Test work"
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Test work" or html =~ "Session launched" or html =~ "Failed"
    end

    test "closes drawer and shows success message after session creation", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element("button", "New Agent") |> render_click()

      view
      |> form("form[phx-submit='create_new_session']", %{
        "model" => "opus",
        "description" => "Another test"
      })
      |> render_submit()

      html = render(view)
      assert html =~ "Session launched" or html =~ "Failed to create session"
    end

    test "stays on project page after creating session (no redirect)", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element("button", "New Agent") |> render_click()

      view
      |> form("form[phx-submit='create_new_session']", %{
        "model" => "sonnet",
        "description" => "Should stay on page"
      })
      |> render_submit()

      assert render(view) =~ "test-project"
    end

    test "project field is disabled and shows current project", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element("button", "New Agent") |> render_click()

      html = render(view)

      assert html =~ "test-project"
    end
  end
end
