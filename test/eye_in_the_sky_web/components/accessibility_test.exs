defmodule EyeInTheSkyWeb.Components.AccessibilityTest do
  @moduledoc """
  Tests for mobile accessibility: 44px touch targets, aria-labels, focus-visible,
  and contrast-improving class presence across interactive components.
  """

  use EyeInTheSkyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.SessionCard
  alias EyeInTheSkyWeb.Components.TaskCard

  defp sample_task(overrides \\ %{}) do
    Map.merge(
      %{
        id: 1,
        uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        title: "Sample task",
        description: "A test task",
        priority: 50,
        state_id: 1,
        state: %{name: "To Do"},
        completed_at: nil,
        due_at: nil,
        agent_id: nil,
        tags: [],
        agents: []
      },
      overrides
    )
  end

  defp sample_session(overrides \\ %{}) do
    Map.merge(
      %{
        id: 1,
        uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        name: "Test Session",
        agent_id: nil,
        project_name: "web",
        started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        ended_at: nil,
        last_activity_at: nil,
        status: "idle",
        active_task: nil,
        intent: nil
      },
      overrides
    )
  end

  describe "TaskCard - aria-labels on icon-only controls" do
    test "kanban copy button has aria-label" do
      task = sample_task()

      html =
        render_component(&TaskCard.task_card/1,
          task: task,
          variant: "kanban",
          on_click: nil,
          on_delete: nil
        )

      assert html =~ ~s(aria-label="Copy task ID")
    end

    test "grid copy button has aria-label" do
      task = sample_task()

      html =
        render_component(&TaskCard.task_card/1,
          task: task,
          variant: "grid",
          on_click: nil,
          on_delete: nil
        )

      assert html =~ ~s(aria-label="Copy task ID")
    end

    test "kanban checkbox button has aria-label for incomplete task" do
      task = sample_task(%{completed_at: nil})

      html =
        render_component(&TaskCard.task_card/1,
          task: task,
          variant: "kanban",
          on_click: nil,
          on_delete: nil
        )

      assert html =~ ~s(aria-label="Mark task complete")
      assert html =~ ~s(aria-pressed="false")
    end

    test "kanban checkbox button has aria-label for completed task" do
      task = sample_task(%{completed_at: "2026-03-01T00:00:00Z"})

      html =
        render_component(&TaskCard.task_card/1,
          task: task,
          variant: "kanban",
          on_click: nil,
          on_delete: nil
        )

      assert html =~ ~s(aria-label="Mark task incomplete")
      assert html =~ ~s(aria-pressed="true")
    end

    test "list row has role=button and aria-label" do
      task = sample_task()

      html =
        render_component(&TaskCard.task_card/1,
          task: task,
          variant: "list",
          on_click: "open_task",
          on_delete: nil
        )

      assert html =~ ~s(role="button")
      assert html =~ ~s(aria-label="Open task Sample task")
    end

    test "list delete button has aria-label" do
      task = sample_task()

      html =
        render_component(&TaskCard.task_card/1,
          task: task,
          variant: "list",
          on_click: "open_task",
          on_delete: "delete_task"
        )

      assert html =~ ~s(aria-label="Delete task")
    end

    test "list delete button has min 44px touch target classes" do
      task = sample_task()

      html =
        render_component(&TaskCard.task_card/1,
          task: task,
          variant: "list",
          on_click: "open_task",
          on_delete: "delete_task"
        )

      assert html =~ "min-h-[44px]"
      assert html =~ "min-w-[44px]"
    end

    test "list DM link has min 44px touch target classes" do
      task = sample_task(%{sessions: [%{uuid: "sess-uuid"}]})

      html =
        render_component(&TaskCard.task_card/1,
          task: task,
          variant: "list",
          on_click: "open_task",
          on_delete: nil
        )

      assert html =~ "min-h-[44px]"
      assert html =~ "min-w-[44px]"
    end
  end

  describe "SessionRow - aria-labels and contrast" do
    test "row has aria-label with session name and status" do
      session = sample_session()

      html =
        render_component(&SessionCard.session_row/1,
          session: session
        )

      assert html =~ ~s(aria-label="Open session: Test Session - Idle")
    end

    test "row is keyboard accessible with role=button and tabindex" do
      session = sample_session()

      html =
        render_component(&SessionCard.session_row/1,
          session: session
        )

      assert html =~ ~s(role="button")
      assert html =~ ~s(tabindex="0")
    end

    test "idle status text uses readable contrast class" do
      session = sample_session(%{status: "idle"})

      html =
        render_component(&SessionCard.session_row/1,
          session: session
        )

      # /55 for "Idle" text
      assert html =~ "text-base-content/55"
    end

    test "completed status text uses readable contrast class" do
      session = sample_session(%{status: "completed"})

      html =
        render_component(&SessionCard.session_row/1,
          session: session
        )

      # /50 for "Done" text
      assert html =~ "text-base-content/50"
    end

    test "project name text uses readable contrast class" do
      session = sample_session()

      html =
        render_component(&SessionCard.session_row/1,
          session: session,
          project_name: "web"
        )

      # /50 for project name
      assert html =~ "text-base-content/50"
    end
  end

  describe "Layout - bottom nav accessible selectors" do
    test "bottom nav has aria-label on nav element", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(aria-label="Main navigation")
    end

    test "bottom nav links have aria-label attributes", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ ~s(aria-label="Sessions")
      assert html =~ ~s(aria-label="Tasks")
      assert html =~ ~s(aria-label="Notes")
      assert html =~ ~s(aria-label="Project")
    end

    test "bottom nav links have min-h-[44px] touch target", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "min-h-[44px]"
    end
  end
end

defmodule EyeInTheSkyWeb.Components.AccessibilityLiveTest do
  @moduledoc """
  LiveView-level accessibility tests requiring DB-created records.
  Must be async: false so the Ecto sandbox is in shared mode and spawned
  LiveView processes can read the same data as the test process.
  """

  use EyeInTheSkyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EyeInTheSky.{Projects, Tasks}

  defp uniq, do: System.unique_integer([:positive])

  defp create_project do
    {:ok, project} =
      Projects.create_project(%{
        name: "a11y-lv-#{uniq()}",
        path: "/tmp/a11y-lv-#{uniq()}",
        slug: "a11y-lv-#{uniq()}"
      })

    project
  end

  defp create_task(project, overrides \\ %{}) do
    {:ok, task} =
      Tasks.create_task(
        Map.merge(
          %{
            uuid: Ecto.UUID.generate(),
            title: "A11y task #{uniq()}",
            state_id: 1,
            project_id: project.id,
            created_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          overrides
        )
      )

    task
  end

  describe "Project tasks list - TaskCard accessibility attributes" do
    test "list row has role=button and aria-label", %{conn: conn} do
      project = create_project()
      _task = create_task(project, %{title: "A11y list task"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/tasks")

      assert html =~ ~s(role="button")
      assert html =~ "Open task A11y list task"
    end

    test "delete button has aria-label", %{conn: conn} do
      project = create_project()
      _task = create_task(project)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/tasks")

      assert html =~ ~s(aria-label="Delete task")
    end

    test "delete button has min-h-[44px] touch target", %{conn: conn} do
      project = create_project()
      _task = create_task(project)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/tasks")

      assert html =~ "min-h-[44px]"
    end
  end

  describe "Kanban - inline card accessibility attributes" do
    test "kanban inline delete button has aria-label", %{conn: conn} do
      project = create_project()
      task = create_task(project, %{title: "Kanban task"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/kanban")

      assert html =~ ~s(aria-label="Delete task #{task.title}")
    end

    test "kanban inline delete button has focus-visible ring", %{conn: conn} do
      project = create_project()
      _task = create_task(project)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/kanban")

      assert html =~ "focus-visible:ring-error"
    end
  end
end
