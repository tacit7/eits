defmodule EyeInTheSkyWeb.ProjectLive.Kanban.DatePickerHandlersTest do
  use EyeInTheSky.DataCase
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.ProjectLive.Kanban.DatePickerHandlers
  alias EyeInTheSky.Tasks
  alias EyeInTheSky.Projects

  setup do
    {:ok, project} =
      Projects.create_project(%{
        name: "Test Project",
        path: "/tmp/test_project"
      })

    {:ok, task} =
      Tasks.create_task(%{
        project_id: project.id,
        title: "Test Task",
        status: "todo"
      })

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        date_picker_year: 2024,
        date_picker_month: 1,
        date_picker_selected: nil,
        show_date_picker: false
      },
      private: %{live_temp: %{}}
    }

    %{socket: socket, task: task, project: project}
  end

  describe "handle_open_date_picker/2" do
    test "opens date picker for task without due date", %{socket: socket, task: task} do
      {:noreply, updated_socket} =
        DatePickerHandlers.handle_open_date_picker(%{"task_id" => task.id}, socket)

      assert updated_socket.assigns.show_date_picker == true
      assert updated_socket.assigns.date_picker_task.id == task.id
    end

    test "sets year and month to today when no due date", %{socket: socket, task: task} do
      {:noreply, updated_socket} =
        DatePickerHandlers.handle_open_date_picker(%{"task_id" => task.id}, socket)

      today = Date.utc_today()
      assert updated_socket.assigns.date_picker_year == today.year
      assert updated_socket.assigns.date_picker_month == today.month
    end

    test "sets year and month to task due date when present", %{socket: socket, project: project} do
      due_date = DateTime.new!(~D[2025-03-15], ~T[12:00:00])

      {:ok, task_with_due} =
        Tasks.create_task(%{
          project_id: project.id,
          title: "Task with due",
          status: "todo",
          due_at: due_date
        })

      {:noreply, updated_socket} =
        DatePickerHandlers.handle_open_date_picker(
          %{"task_id" => task_with_due.id},
          socket
        )

      assert updated_socket.assigns.date_picker_year == 2025
      assert updated_socket.assigns.date_picker_month == 3
    end

    test "sets selected date from task due date", %{socket: socket, project: project} do
      due_date = DateTime.new!(~D[2025-03-15], ~T[12:00:00])

      {:ok, task_with_due} =
        Tasks.create_task(%{
          project_id: project.id,
          title: "Task with due",
          status: "todo",
          due_at: due_date
        })

      {:noreply, updated_socket} =
        DatePickerHandlers.handle_open_date_picker(
          %{"task_id" => task_with_due.id},
          socket
        )

      assert updated_socket.assigns.date_picker_selected == "2025-03-15"
    end
  end

  describe "handle_close_date_picker/1" do
    test "closes date picker", %{socket: socket} do
      open_socket = Map.put(socket.assigns, :show_date_picker, true)
      open_socket = socket |> Map.put(:assigns, open_socket)

      {:noreply, updated_socket} = DatePickerHandlers.handle_close_date_picker(open_socket)

      assert updated_socket.assigns.show_date_picker == false
    end
  end

  describe "handle_date_picker_prev_month/1" do
    test "moves to previous month", %{socket: socket} do
      socket = put_in(socket.assigns, [:date_picker_year], 2024)
      socket = put_in(socket.assigns, [:date_picker_month], 3)

      {:noreply, updated_socket} = DatePickerHandlers.handle_date_picker_prev_month(socket)

      assert updated_socket.assigns.date_picker_month == 2
      assert updated_socket.assigns.date_picker_year == 2024
    end

    test "wraps to previous year when moving from January", %{socket: socket} do
      socket = put_in(socket.assigns, [:date_picker_year], 2024)
      socket = put_in(socket.assigns, [:date_picker_month], 1)

      {:noreply, updated_socket} = DatePickerHandlers.handle_date_picker_prev_month(socket)

      assert updated_socket.assigns.date_picker_month == 12
      assert updated_socket.assigns.date_picker_year == 2023
    end
  end

  describe "handle_date_picker_next_month/1" do
    test "moves to next month", %{socket: socket} do
      socket = put_in(socket.assigns, [:date_picker_year], 2024)
      socket = put_in(socket.assigns, [:date_picker_month], 3)

      {:noreply, updated_socket} = DatePickerHandlers.handle_date_picker_next_month(socket)

      assert updated_socket.assigns.date_picker_month == 4
      assert updated_socket.assigns.date_picker_year == 2024
    end

    test "wraps to next year when moving from December", %{socket: socket} do
      socket = put_in(socket.assigns, [:date_picker_year], 2024)
      socket = put_in(socket.assigns, [:date_picker_month], 12)

      {:noreply, updated_socket} = DatePickerHandlers.handle_date_picker_next_month(socket)

      assert updated_socket.assigns.date_picker_month == 1
      assert updated_socket.assigns.date_picker_year == 2025
    end
  end

  describe "handle_select_due_date/2" do
    test "selects due date", %{socket: socket} do
      {:noreply, updated_socket} =
        DatePickerHandlers.handle_select_due_date(%{"date" => "2025-03-15"}, socket)

      assert updated_socket.assigns.date_picker_selected == "2025-03-15"
    end

    test "clears selected date", %{socket: socket} do
      {:noreply, updated_socket} =
        DatePickerHandlers.handle_select_due_date(%{"date" => ""}, socket)

      assert updated_socket.assigns.date_picker_selected == ""
    end
  end

  describe "handle_save_due_date/2" do
    test "saves due date to task", %{socket: socket, task: task} do
      {:noreply, updated_socket} =
        DatePickerHandlers.handle_save_due_date(
          %{"task_id" => task.id, "due_at" => "2025-03-15"},
          socket
        )

      assert updated_socket.assigns.show_date_picker == false
    end

    test "clears due date when empty string", %{socket: socket, task: task} do
      {:noreply, updated_socket} =
        DatePickerHandlers.handle_save_due_date(
          %{"task_id" => task.id, "due_at" => ""},
          socket
        )

      assert updated_socket.assigns.show_date_picker == false
    end
  end

  describe "handle_remove_due_date/2" do
    test "removes due date from task", %{socket: socket, project: project} do
      due_date = DateTime.new!(~D[2025-03-15], ~T[12:00:00])

      {:ok, task_with_due} =
        Tasks.create_task(%{
          project_id: project.id,
          title: "Task with due",
          status: "todo",
          due_at: due_date
        })

      {:noreply, updated_socket} =
        DatePickerHandlers.handle_remove_due_date(%{"task_id" => task_with_due.id}, socket)

      assert updated_socket.assigns.show_date_picker == false
    end
  end
end
