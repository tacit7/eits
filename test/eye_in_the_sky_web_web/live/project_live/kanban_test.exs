defmodule EyeInTheSkyWebWeb.ProjectLive.KanbanTest do
  use EyeInTheSkyWebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.{Projects, Tasks}

  defp uniq, do: System.unique_integer([:positive])

  defp create_project do
    {:ok, project} =
      Projects.create_project(%{
        name: "kanban-test-#{uniq()}",
        path: "/tmp/kanban-test-#{uniq()}",
        slug: "kanban-test-#{uniq()}"
      })

    project
  end

  defp create_task(project, overrides \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            title: "Test task #{uniq()}",
            state_id: 1,
            project_id: project.id,
            created_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          overrides
        )
      )

    task
  end

  describe "mount" do
    test "renders kanban columns for workflow states", %{conn: conn} do
      project = create_project()
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/kanban")

      assert html =~ "To Do"
      assert html =~ "In Progress"
      assert html =~ "Done"
    end

    test "renders tasks in correct columns", %{conn: conn} do
      project = create_project()
      task = create_task(project, %{title: "My Kanban Task", state_id: 1})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/kanban")

      assert html =~ task.title
    end

    test "shows New Task button", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      assert has_element?(view, "button", "New Task")
    end

    test "handles invalid project id gracefully", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/projects/notanid/kanban")

      assert html =~ "Invalid project ID"
    end
  end

  describe "quick-add" do
    test "shows add task input when clicking add task button", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      # click the "Add task" button for state_id 1 (To Do)
      view
      |> element("[phx-click='show_quick_add'][phx-value-state_id='1']")
      |> render_click()

      assert has_element?(view, "input[name='title']")
    end

    test "hides quick-add input via hide_quick_add event", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='show_quick_add'][phx-value-state_id='1']")
      |> render_click()

      # quick-add input is inside the kanban column container
      assert has_element?(view, "#kanban-col-1 input[name='title']")

      render_click(view, "hide_quick_add", %{})

      refute has_element?(view, "#kanban-col-1 input[name='title']")
    end

    test "creates task via quick-add form", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='show_quick_add'][phx-value-state_id='1']")
      |> render_click()

      view
      |> form("form[phx-submit='quick_add_task']", %{"title" => "Quick task", "state_id" => "1"})
      |> render_submit()

      assert render(view) =~ "Quick task"
    end

    test "ignores quick-add with blank title", %{conn: conn} do
      project = create_project()
      task_count_before = length(Tasks.list_tasks())

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='show_quick_add'][phx-value-state_id='1']")
      |> render_click()

      view
      |> form("form[phx-submit='quick_add_task']", %{"title" => "   ", "state_id" => "1"})
      |> render_submit()

      assert length(Tasks.list_tasks()) == task_count_before
    end
  end

  describe "new task drawer" do
    test "opens drawer on New Task click", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view |> element("button", "New Task") |> render_click()

      html = render(view)
      assert html =~ "state_id"
    end

    test "creates task from drawer form", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view |> element("button", "New Task") |> render_click()

      view
      |> form("form[phx-submit='create_new_task']", %{
        "title" => "Drawer Task",
        "description" => "From drawer",
        "state_id" => "1",
        "priority" => "1",
        "tags" => ""
      })
      |> render_submit()

      assert render(view) =~ "Task created successfully"
    end
  end

  describe "task detail drawer" do
    test "opens task detail drawer on card click", %{conn: conn} do
      project = create_project()
      task = create_task(project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      assert render(view) =~ task.title
    end

    test "updates task from detail drawer", %{conn: conn} do
      project = create_project()
      task = create_task(project, %{title: "Original Title"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      view
      |> form("form[phx-submit='update_task']", %{
        "title" => "Updated Title",
        "description" => "",
        "state_id" => "1",
        "priority" => "0",
        "due_at" => "",
        "tags" => ""
      })
      |> render_submit()

      assert render(view) =~ "Task updated successfully"
      assert render(view) =~ "Updated Title"
    end

    test "deletes task from detail drawer", %{conn: conn} do
      project = create_project()
      task = create_task(project, %{title: "Task To Delete"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      # Use the drawer's delete button (has data-confirm attribute, distinct from card inline button)
      view
      |> element(
        "button[data-confirm][phx-click='delete_task'][phx-value-task_id='#{task.uuid}']"
      )
      |> render_click()

      refute render(view) =~ "Task To Delete"
    end
  end

  describe "PubSub" do
    test "ignores :tasks_changed broadcast for a different project", %{conn: conn} do
      project = create_project()
      other_project = create_project()

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      other_task = create_task(other_project, %{title: "Other Project Task"})

      # Broadcast only on other project's scoped topic — kanban should not reload
      Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "tasks:#{other_project.id}", :tasks_changed)

      :timer.sleep(50)

      refute render(view) =~ other_task.title
    end

    test "reloads tasks on :tasks_changed for correct project", %{conn: conn} do
      project = create_project()

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      task = create_task(project, %{title: "PubSub Task"})
      Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "tasks:#{project.id}", :tasks_changed)

      :timer.sleep(50)

      assert render(view) =~ task.title
    end

    test "refreshes open selected_task when :tasks_changed fires", %{conn: conn} do
      project = create_project()
      task = create_task(project, %{title: "Before Update"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> element("[phx-click='open_task_detail'][phx-value-task_id='#{task.uuid}']")
      |> render_click()

      assert render(view) =~ "Before Update"

      Tasks.update_task(task, %{title: "After Update"})
      Phoenix.PubSub.broadcast(EyeInTheSkyWeb.PubSub, "tasks:#{project.id}", :tasks_changed)

      :timer.sleep(50)

      assert render(view) =~ "After Update"
    end
  end

  describe "search" do
    test "filters tasks by title when query >= 4 chars", %{conn: conn} do
      project = create_project()
      _task1 = create_task(project, %{title: "Searchable task zzzz"})
      _task2 = create_task(project, %{title: "Different work xxxx"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> form("form[phx-change='search']", %{"query" => "zzzz"})
      |> render_change()

      html = render(view)
      assert html =~ "Searchable task zzzz"
      refute html =~ "Different work xxxx"
    end

    test "shows all tasks when query is less than 4 chars", %{conn: conn} do
      project = create_project()
      _task1 = create_task(project, %{title: "Alpha task"})
      _task2 = create_task(project, %{title: "Beta task"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/kanban")

      view
      |> form("form[phx-change='search']", %{"query" => "al"})
      |> render_change()

      html = render(view)
      assert html =~ "Alpha task"
      assert html =~ "Beta task"
    end
  end
end
