defmodule EyeInTheSkyWeb.Live.Shared.BulkHelpers do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 2]

  alias EyeInTheSky.Tasks

  def handle_toggle_bulk_mode(socket) do
    {:noreply,
     socket
     |> assign(:bulk_mode, !socket.assigns.bulk_mode)
     |> assign(:selected_tasks, MapSet.new())}
  end

  def handle_toggle_select_task(%{"task-uuid" => uuid}, socket) do
    selected = socket.assigns.selected_tasks

    updated =
      if MapSet.member?(selected, uuid),
        do: MapSet.delete(selected, uuid),
        else: MapSet.put(selected, uuid)

    {:noreply, assign(socket, :selected_tasks, updated)}
  end

  def handle_toggle_select_task(_params, socket), do: {:noreply, socket}

  def handle_select_all_column(%{"state-id" => state_id_str}, socket) do
    state_id = parse_int(state_id_str, 0)

    column_uuids =
      Map.get(socket.assigns.tasks_by_state, state_id, [])
      |> Enum.map(& &1.uuid)
      |> Enum.reject(&is_nil/1)

    current = socket.assigns.selected_tasks
    all_selected = Enum.all?(column_uuids, &MapSet.member?(current, &1))

    updated =
      if all_selected,
        do: Enum.reduce(column_uuids, current, &MapSet.delete(&2, &1)),
        else: Enum.reduce(column_uuids, current, &MapSet.put(&2, &1))

    {:noreply, assign(socket, :selected_tasks, updated)}
  end

  def handle_bulk_move(%{"state_id" => state_id_str}, socket, reload_fn) do
    state_id = parse_int(state_id_str, 0)
    now = DateTime.utc_now()

    socket.assigns.selected_tasks
    |> Enum.reject(&is_nil/1)
    |> Enum.each(fn uuid ->
      task = Tasks.get_task_by_uuid!(uuid)
      Tasks.update_task(task, %{state_id: state_id, updated_at: now})
    end)

    {:noreply, socket |> assign(:selected_tasks, MapSet.new()) |> reload_fn.()}
  end

  def handle_bulk_archive(socket, reload_fn) do
    socket.assigns.selected_tasks
    |> Enum.reject(&is_nil/1)
    |> Enum.each(fn uuid ->
      task = Tasks.get_task_by_uuid!(uuid)
      Tasks.archive_task(task)
    end)

    {:noreply,
     socket
     |> assign(:selected_tasks, MapSet.new())
     |> reload_fn.()
     |> put_flash(:info, "Tasks archived")}
  end

  def handle_bulk_delete(socket, reload_fn) do
    socket.assigns.selected_tasks
    |> Enum.reject(&is_nil/1)
    |> Enum.each(fn uuid ->
      task = Tasks.get_task_by_uuid!(uuid)
      Tasks.delete_task_with_associations(task)
    end)

    {:noreply,
     socket
     |> assign(:selected_tasks, MapSet.new())
     |> reload_fn.()
     |> put_flash(:info, "Tasks deleted")}
  end
end
