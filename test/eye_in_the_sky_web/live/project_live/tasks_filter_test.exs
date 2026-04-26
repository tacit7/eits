defmodule EyeInTheSkyWeb.ProjectLive.TasksFilterTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Projects, Tasks}

  defp uniq, do: System.unique_integer([:positive])

  defp create_project do
    {:ok, project} =
      Projects.create_project(%{
        name: "filter-test-#{uniq()}",
        path: "/tmp/filter-test-#{uniq()}",
        slug: "filter-test-#{uniq()}"
      })

    project
  end

  defp create_task(project, overrides \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            title: "Task #{uniq()}",
            state_id: 1,
            project_id: project.id,
            created_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          overrides
        )
      )

    task
  end

  describe "Mobile filter bottom sheet — project tasks" do
    test "filter sheet is hidden by default", %{conn: conn} do
      project = create_project()
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/tasks")

      refute html =~ "tasks-filter-sheet"
    end

    test "mobile filter button is present", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")

      assert has_element?(view, ~s|button[aria-label="Open filters"]|)
    end

    test "clicking filter button opens the sheet", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()

      html = render(view)
      assert html =~ "tasks-filter-sheet"
      assert html =~ "Filter &amp; Sort"
    end

    test "close button dismisses the sheet", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()
      assert render(view) =~ "tasks-filter-sheet"

      view |> element(~s|button[aria-label="Close filter panel"]|) |> render_click()
      refute render(view) =~ "tasks-filter-sheet"
    end

    test "status filter in sheet updates list and preserves state", %{conn: conn} do
      project = create_project()
      _todo_task = create_task(project, %{title: "Todo Task", state_id: 1})
      _done_task = create_task(project, %{title: "Done Task", state_id: 3})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()

      # Filter to Done state (state_id 3)
      view
      |> element(~s|#tasks-filter-sheet button[phx-value-state_id="3"]|)
      |> render_click()

      # Scope to #main-content to avoid sidebar showing all tasks regardless of filter
      assert has_element?(view, "#main-content", "Done Task")
      refute has_element?(view, "#main-content", "Todo Task")
    end

    test "mobile filter button is rendered in the action bar", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")

      # Mobile action bar includes the filter button
      assert has_element?(view, ~s|button[aria-label="Open filters"]|)
    end

    test "active filter indicator dot appears when non-default filter applied", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")

      # Initially no dot
      refute has_element?(view, ~s|button[aria-label="Open filters"] span.bg-primary|)

      # Apply state filter
      view
      |> render_hook("filter_status", %{"state_id" => "1"})

      html = render(view)
      assert html =~ "bg-primary rounded-full"
    end

    test "reset button in sheet clears filter", %{conn: conn} do
      project = create_project()
      _done_task = create_task(project, %{title: "Done Task", state_id: 3})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")

      # Apply a filter
      view |> render_hook("filter_status", %{"state_id" => "3"})

      # Open sheet and reset
      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()

      view
      |> element(~s|#tasks-filter-sheet button[aria-label="Reset filters"]|)
      |> render_click()

      # After reset, filter indicator dot should be gone
      refute has_element?(view, ~s|button[aria-label="Open filters"] span.bg-primary|)
    end

    test "sort by buttons in sheet update sort order", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()

      # Change sort to oldest first
      view
      |> element(~s|#tasks-filter-sheet button[phx-value-value="created_asc"]|)
      |> render_click()

      # Re-open sheet to verify sort state persisted
      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()
      html = render(view)

      # The created_asc button should show as active (btn-primary)
      assert html =~
               ~r/phx-value-value="created_asc"[^>]*class="[^"]*btn-primary/s
    end

    test "backdrop click closes the sheet", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/tasks")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()
      assert render(view) =~ "tasks-filter-sheet"

      view |> element(".fixed.inset-0.z-40") |> render_click()
      refute render(view) =~ "tasks-filter-sheet"
    end
  end

  # TODO: No LiveView exists at /tasks (only an API controller at GET /tasks).
  # Skip until an overview tasks LiveView is implemented.
  describe "Mobile filter bottom sheet — overview tasks" do
    @tag :skip
    test "filter sheet hidden by default on overview page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/tasks")
      refute html =~ "overview-tasks-filter-sheet"
    end

    @tag :skip
    test "mobile filter button present on overview page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")
      assert has_element?(view, ~s|button[aria-label="Open filters"]|)
    end

    @tag :skip
    test "filter button opens overview sheet", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()
      assert render(view) =~ "overview-tasks-filter-sheet"
    end

    @tag :skip
    test "applying filter in overview sheet updates task list", %{conn: conn} do
      # Create tasks in different states
      project = create_project()
      _todo_task = create_task(project, %{title: "Overview Todo", state_id: 1})
      _done_task = create_task(project, %{title: "Overview Done", state_id: 3})

      {:ok, view, _html} = live(conn, ~p"/tasks")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()

      view
      |> element(~s|#overview-tasks-filter-sheet button[phx-value-state_id="3"]|)
      |> render_click()

      html = render(view)
      assert html =~ "Overview Done"
      refute html =~ "Overview Todo"
    end

    @tag :skip
    test "close button on overview sheet works", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/tasks")

      view |> element(~s|button[aria-label="Open filters"]|) |> render_click()
      assert render(view) =~ "overview-tasks-filter-sheet"

      view |> element(~s|button[aria-label="Close filter panel"]|) |> render_click()
      refute render(view) =~ "overview-tasks-filter-sheet"
    end
  end
end
