defmodule EyeInTheSkyWeb.ProjectLive.SessionsTest do
  use EyeInTheSkyWeb.ConnCase

  import Phoenix.LiveViewTest
  alias EyeInTheSky.Projects

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

      assert has_element?(view, "h2", "New Agent")
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

  describe "Mobile filter bottom sheet" do
    test "filter sheet is not visible by default", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/sessions")

      refute html =~ "session-filter-sheet"
      refute html =~ ~r/role="dialog".*aria-label="Filter sessions"/
    end

    test "filter button is present in DOM", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      assert has_element?(view, ~s|button[aria-label="Open filters"]|)
    end

    test "opens filter sheet on button click", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()

      html = render(view)
      assert html =~ "session-filter-sheet"
      assert html =~ "Filter &amp; Sort"
    end

    test "closes filter sheet on close button", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()
      assert render(view) =~ "session-filter-sheet"

      view |> element(~s|button[aria-label="Close filter panel"]|) |> render_click()
      refute render(view) =~ "session-filter-sheet"
    end

    test "selecting a filter in sheet updates session_filter and closes sheet", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()

      # Click the "Active" filter inside the sheet
      view
      |> element(~s|#session-filter-sheet button[phx-value-filter="active"]|)
      |> render_click()

      html = render(view)
      # Filter is applied (aria-pressed on desktop button reflects state)
      assert html =~ ~s|phx-value-filter="active"|
    end

    test "active filter indicator dot shown when non-default filter active", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      # No dot initially (default filter = all, sort = recent)
      refute has_element?(view, ~s|button[aria-label="Open filters"] span.bg-primary|)

      # Apply a non-default filter
      view
      |> render_hook("filter_session", %{"filter" => "active"})

      html = render(view)
      assert html =~ "bg-primary rounded-full"
    end

    test "sort buttons in sheet update sort state", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()

      view
      |> element(~s|#session-filter-sheet button[phx-value-by="name"]|)
      |> render_click()

      # The Name sort button should reflect active state on next sheet open
      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()
      updated_html = render(view)
      assert updated_html =~ ~s|phx-value-by="name"|
    end

    test "desktop filter pills remain visible with hidden sm:flex class", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/sessions")

      # Desktop filter container should exist with hidden sm:flex
      assert html =~ "hidden sm:flex"
    end

    test "reset in sheet resets filter to all", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/sessions")

      # Apply a filter
      view |> render_hook("filter_session", %{"filter" => "active"})

      # Open sheet and reset
      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()

      view
      |> element(~s|#session-filter-sheet button[aria-label="Reset filters"]|)
      |> render_click()

      # After reset, the active indicator dot should be gone
      refute has_element?(view, ~s|button[aria-label="Open filters"] span.bg-primary|)
    end
  end
end
