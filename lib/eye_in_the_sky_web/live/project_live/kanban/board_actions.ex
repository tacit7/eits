defmodule EyeInTheSkyWeb.ProjectLive.Kanban.BoardActions do
  @moduledoc """
  Board-specific action handlers for the Kanban LiveView.

  Covers column/task ordering, drag-drop moves, quick-add UI,
  tag color cycling, and column archiving.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 2]

  alias EyeInTheSky.Tasks
  alias EyeInTheSkyWeb.Live.Shared.KanbanFilters

  @tag_colors ~w(#6B7280 #EF4444 #F59E0B #10B981 #3B82F6 #8B5CF6 #EC4899 #06B6D4)

  def handle_cycle_tag_color(%{"tag-id" => tag_id_str}, socket) do
    tag_id = parse_int(tag_id_str, 0)
    tag = Tasks.get_tag!(tag_id)
    current_color = tag.color || List.first(@tag_colors)
    current_idx = Enum.find_index(@tag_colors, &(&1 == current_color)) || -1
    next_color = Enum.at(@tag_colors, rem(current_idx + 1, length(@tag_colors)))

    case Tasks.update_tag(tag, %{color: next_color}) do
      {:ok, _} -> {:noreply, KanbanFilters.load_tasks(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_reorder_columns(%{"column_ids" => column_ids}, socket) when is_list(column_ids) do
    ids = Enum.map(column_ids, &parse_int(&1, 0))
    Tasks.reorder_workflow_states(ids)
    {:noreply, assign(socket, :workflow_states, Tasks.list_workflow_states())}
  end

  def handle_reorder_tasks(%{"task_ids" => task_ids}, socket) when is_list(task_ids) do
    Tasks.reorder_tasks(task_ids)
    {:noreply, socket}
  end

  def handle_move_task(%{"task_id" => task_uuid, "state_id" => state_id_str}, socket) do
    state_id = parse_int(state_id_str, 0)
    task = Tasks.get_task_by_uuid!(task_uuid)

    case Tasks.update_task(task, %{
           state_id: state_id,
           updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
         }) do
      {:ok, _} -> {:noreply, KanbanFilters.load_tasks(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to move task")}
    end
  end

  def handle_show_quick_add(%{"state_id" => state_id}, socket) do
    {:noreply, assign(socket, :quick_add_column, parse_int(state_id, 0))}
  end

  def handle_hide_quick_add(socket) do
    {:noreply, assign(socket, :quick_add_column, nil)}
  end

  def handle_archive_column(%{"state-id" => state_id_str}, socket) do
    state_id = parse_int(state_id_str, 0)
    column_tasks = Map.get(socket.assigns.tasks_by_state, state_id, [])
    Enum.each(column_tasks, fn task -> Tasks.archive_task(task) end)

    {:noreply,
     socket
     |> KanbanFilters.load_tasks()
     |> put_flash(:info, "#{length(column_tasks)} tasks archived")}
  end
end
