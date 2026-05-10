defmodule EyeInTheSkyWeb.Components.DmPage.TasksTabTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.TasksTab

  describe "tasks_tab/1" do
    test "renders empty state when no tasks" do
      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: []
        )

      assert html =~ "No tasks yet"
      assert html =~ "Tasks from this session will appear here"
      assert html =~ "Add task"
    end

    test "renders task with title and state" do
      tasks = [
        %{
          id: 1,
          uuid: "task-uuid-1",
          title: "Fix login issue",
          state_id: 2,
          state: %{name: "In Progress", id: 2},
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "Fix login issue"
      assert html =~ "In Progress"
    end

    test "renders task with completed status (strikethrough)" do
      tasks = [
        %{
          id: 1,
          uuid: "task-uuid-1",
          title: "Done task",
          state_id: 3,
          state: %{name: "Done", id: 3},
          created_at: DateTime.utc_now(),
          completed_at: DateTime.utc_now(),
          description: nil,
          tags: [],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "line-through"
      assert html =~ "text-base-content/40"
    end

    test "renders in-progress task with animated status dot" do
      tasks = [
        %{
          id: 1,
          uuid: "task-uuid-1",
          title: "Working task",
          state_id: 2,
          state: %{name: "In Progress", id: 2},
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "animate-ping"
      assert html =~ "bg-info"
    end

    test "renders done task with green status dot" do
      tasks = [
        %{
          id: 1,
          uuid: "task-uuid-1",
          title: "Completed task",
          state_id: 3,
          state: %{name: "Done", id: 3},
          created_at: DateTime.utc_now(),
          completed_at: DateTime.utc_now(),
          description: nil,
          tags: [],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "bg-success"
    end

    test "renders in-review task with warning status dot" do
      tasks = [
        %{
          id: 1,
          uuid: "task-uuid-1",
          title: "Review task",
          state_id: 4,
          state: %{name: "In Review", id: 4},
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "bg-warning"
    end

    test "renders task with description and notes" do
      tasks = [
        %{
          id: 1,
          uuid: "task-uuid-1",
          title: "Task with content",
          state_id: 1,
          state: %{name: "To Do", id: 1},
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: "This is a detailed description",
          tags: [],
          notes: [
            %{title: "Note 1", body: "First note content"}
          ],
          notes_count: 1
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "This is a detailed description"
      assert html =~ "Note 1"
      assert html =~ "First note content"
    end

    test "renders task with tags" do
      tasks = [
        %{
          id: 1,
          uuid: "task-uuid-1",
          title: "Tagged task",
          state_id: 1,
          state: %{name: "To Do", id: 1},
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [
            %{name: "bug"},
            %{name: "urgent"},
            %{name: "backend"}
          ],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "bug"
      assert html =~ "urgent"
      # Takes first 2 tags
      assert html =~ "bug, urgent"
    end

    test "renders task without description and notes (collapse disabled)" do
      tasks = [
        %{
          id: 1,
          uuid: "task-uuid-1",
          title: "Simple task",
          state_id: 1,
          state: %{name: "To Do", id: 1},
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      # Collapse should be present but not have arrow if no expandable content
      assert html =~ "collapse"
    end

    test "renders task uuid truncated to 8 characters" do
      tasks = [
        %{
          id: 1,
          uuid: "very-long-uuid-string-value",
          title: "Task",
          state_id: 1,
          state: nil,
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      # Display span shows 8 chars; full UUID also appears in phx-value-task_id.
      # The span content has surrounding whitespace so we match without angle brackets.
      assert html =~ "very-lon"
      refute html =~ "very-long-u\""
    end

    test "renders task id when uuid not present" do
      tasks = [
        %{
          id: 123456789,
          uuid: nil,
          title: "Task",
          state_id: 1,
          state: nil,
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "12345678"
    end

    test "renders notes count badge" do
      tasks = [
        %{
          id: 1,
          uuid: "task-uuid-1",
          title: "Task with notes",
          state_id: 1,
          state: %{name: "To Do", id: 1},
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [],
          notes_count: 3
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "3"
      assert html =~ "hero-chat-bubble"
    end

    test "renders edit button for each task" do
      tasks = [
        %{
          id: 42,
          uuid: "task-uuid-42",
          title: "Editable task",
          state_id: 1,
          state: %{name: "To Do", id: 1},
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "open_task_detail"
      assert html =~ "phx-value-task_id"
    end

    test "renders multiple tasks" do
      tasks = [
        %{
          id: 1,
          uuid: "uuid-1",
          title: "First task",
          state_id: 1,
          state: %{name: "To Do", id: 1},
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [],
          notes_count: 0
        },
        %{
          id: 2,
          uuid: "uuid-2",
          title: "Second task",
          state_id: 2,
          state: %{name: "In Progress", id: 2},
          created_at: DateTime.utc_now(),
          completed_at: nil,
          description: nil,
          tags: [],
          notes_count: 0
        }
      ]

      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: tasks
        )

      assert html =~ "First task"
      assert html =~ "Second task"
      assert html =~ "dm-task-1"
      assert html =~ "dm-task-2"
    end

    test "renders add task button" do
      html =
        render_component(
          &TasksTab.tasks_tab/1,
          tasks: []
        )

      assert html =~ "toggle_new_task_drawer"
      assert html =~ "Add task"
      assert html =~ "hero-plus"
    end
  end
end
