defmodule EyeInTheSkyWeb.Live.Shared.TasksHelpersTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.{Projects, Tasks}
  alias EyeInTheSkyWeb.Live.Shared.TasksHelpers

  defp uniq, do: System.unique_integer([:positive])

  defp create_project do
    {:ok, project} =
      Projects.create_project(%{
        name: "helpers-test-#{uniq()}",
        path: "/tmp/helpers-test-#{uniq()}",
        slug: "helpers-test-#{uniq()}"
      })

    project
  end

  describe "handle_create_new_task/3" do
    test "creates a task from form params with string integers" do
      project = create_project()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          project_id: project.id,
          session_id: nil,
          show_new_task_drawer: true,
          show_create_task_drawer: false,
          flash: %{},
          __changed__: %{}
        }
      }

      params = %{
        "title" => "Test task",
        "description" => "A description",
        "state_id" => "1",
        "priority" => "2",
        "tags" => ""
      }

      reload_fn = fn socket -> socket end

      {:noreply, result_socket} = TasksHelpers.handle_create_new_task(params, socket, reload_fn)
      assert result_socket.assigns.show_new_task_drawer == false
    end

    test "handles lenient integer parsing (trailing whitespace)" do
      project = create_project()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          project_id: project.id,
          session_id: nil,
          show_new_task_drawer: true,
          show_create_task_drawer: false,
          flash: %{},
          __changed__: %{}
        }
      }

      params = %{
        "title" => "Lenient parse test",
        "description" => "",
        "state_id" => "1 ",
        "priority" => "2 ",
        "tags" => ""
      }

      reload_fn = fn socket -> socket end

      {:noreply, result_socket} = TasksHelpers.handle_create_new_task(params, socket, reload_fn)
      assert result_socket.assigns.show_new_task_drawer == false

      # Verify the task was created with correct parsed values
      [task | _] = Tasks.list_tasks(limit: 1)
      assert task.title == "Lenient parse test"
      assert task.state_id == 1
      assert task.priority == 2
    end

    test "parses comma-separated tags and assigns them" do
      project = create_project()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          project_id: project.id,
          session_id: nil,
          show_new_task_drawer: true,
          show_create_task_drawer: false,
          flash: %{},
          __changed__: %{}
        }
      }

      params = %{
        "title" => "Tagged task",
        "description" => "",
        "state_id" => "1",
        "priority" => "1",
        "tags" => "bug, urgent, frontend"
      }

      reload_fn = fn socket -> socket end

      {:noreply, _socket} = TasksHelpers.handle_create_new_task(params, socket, reload_fn)

      [task | _] = Tasks.list_tasks(limit: 1)
      assert task.title == "Tagged task"
      tag_names = Enum.map(task.tags, & &1.name) |> Enum.sort()
      assert tag_names == ["bug", "frontend", "urgent"]
    end

    test "defaults state_id to todo when zero" do
      project = create_project()

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          project_id: project.id,
          session_id: nil,
          show_new_task_drawer: true,
          show_create_task_drawer: false,
          flash: %{},
          __changed__: %{}
        }
      }

      params = %{
        "title" => "Default state task",
        "description" => "",
        "state_id" => "0",
        "priority" => "1",
        "tags" => ""
      }

      reload_fn = fn socket -> socket end

      {:noreply, _socket} = TasksHelpers.handle_create_new_task(params, socket, reload_fn)

      [task | _] = Tasks.list_tasks(limit: 1)
      assert task.state_id == Tasks.WorkflowState.todo_id()
    end
  end
end
