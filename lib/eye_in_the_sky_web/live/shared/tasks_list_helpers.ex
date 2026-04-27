defmodule EyeInTheSkyWeb.Live.Shared.TasksListHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [stream: 4, stream_insert: 3]

  @per_page 50

  # Resets to page 1, replaces the task list.
  # search_fn/1 receives the query string.
  # list_fn/1 receives a keyword list of options (limit, offset, state_id, sort_by).
  # count_fn/1 receives a keyword list of options (state_id).
  # Side effects: resets selected_task_ids + tasks_select_mode + loaded_task_ids + loaded_tasks.
  def load_tasks(socket, search_fn, list_fn, count_fn) do
    query = socket.assigns.search_query
    filter_state_id = socket.assigns.filter_state_id
    sort_by = socket.assigns.sort_by

    if query != "" and String.trim(query) != "" do
      tasks = search_fn.(query)

      tasks =
        if filter_state_id,
          do: Enum.filter(tasks, &(&1.state_id == filter_state_id)),
          else: tasks

      socket
      |> assign(:task_count, length(tasks))
      |> assign(:page, 1)
      |> assign(:has_more, false)
      |> assign(:total_tasks, length(tasks))
      |> assign(:loaded_task_ids, Enum.map(tasks, &task_id/1))
      |> assign(:loaded_tasks, tasks)
      |> assign(:selected_task_ids, MapSet.new())
      |> assign(:tasks_select_mode, false)
      |> stream(:tasks, tasks, reset: true)
    else
      total = count_fn.(state_id: filter_state_id)
      tasks = list_fn.(limit: @per_page, offset: 0, state_id: filter_state_id, sort_by: sort_by)

      socket
      |> assign(:task_count, length(tasks))
      |> assign(:page, 1)
      |> assign(:has_more, length(tasks) < total)
      |> assign(:total_tasks, total)
      |> assign(:loaded_task_ids, Enum.map(tasks, &task_id/1))
      |> assign(:loaded_tasks, tasks)
      |> assign(:selected_task_ids, MapSet.new())
      |> assign(:tasks_select_mode, false)
      |> stream(:tasks, tasks, reset: true)
    end
  end

  # Appends the next page to the existing task list.
  # list_fn/1 receives a keyword list of options (limit, offset, state_id, sort_by).
  def load_tasks_page(socket, page, list_fn) do
    filter_state_id = socket.assigns.filter_state_id
    sort_by = socket.assigns.sort_by
    offset = (page - 1) * @per_page
    total = socket.assigns.total_tasks

    new_tasks =
      list_fn.(limit: @per_page, offset: offset, state_id: filter_state_id, sort_by: sort_by)

    new_ids = Enum.map(new_tasks, &task_id/1)

    socket =
      socket
      |> update(:task_count, &(&1 + length(new_tasks)))
      |> assign(:page, page)
      |> assign(:has_more, offset + length(new_tasks) < total)
      |> update(:loaded_task_ids, &(&1 ++ new_ids))
      |> update(:loaded_tasks, &(&1 ++ new_tasks))

    Enum.reduce(new_tasks, socket, fn task, acc ->
      stream_insert(acc, :tasks, task)
    end)
  end

  # Returns the stable string ID used for selection tracking.
  # Prefers UUID when available (tasks created via eits CLI have UUIDs),
  # falls back to integer ID as a string.
  defp task_id(task), do: task.uuid || to_string(task.id)
end
