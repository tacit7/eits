defmodule EyeInTheSkyWeb.Live.Shared.KanbanFilters do
  @moduledoc """
  Filter logic for the kanban board.

  Extracted from Kanban LiveView to keep the board focused on
  mount, event routing, and rendering. Delegates pure filter
  functions to EyeInTheSky.TaskFilter for independent testing.
  """

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.TaskFilter

  # ---------------------------------------------------------------------------
  # Public: apply all active filters to the socket's task list
  # ---------------------------------------------------------------------------

  def apply_filters(socket) do
    tasks = socket.assigns.tasks
    priority_filter = socket.assigns.filter_priority
    filter_tags = socket.assigns.filter_tags
    tag_mode = socket.assigns.filter_tag_mode
    filter_due_date = socket.assigns.filter_due_date
    filter_activity = socket.assigns.filter_activity

    filtered =
      tasks
      |> TaskFilter.filter_by_priority(priority_filter)
      |> TaskFilter.filter_by_tags(filter_tags, tag_mode)
      |> TaskFilter.filter_by_due_date(filter_due_date)
      |> TaskFilter.filter_by_activity(filter_activity)

    tasks_by_state =
      Enum.group_by(filtered, fn task ->
        if task.state, do: task.state.id, else: nil
      end)

    assign(socket, :tasks_by_state, tasks_by_state)
  end

  # ---------------------------------------------------------------------------
  # Filter parsers (string value → atom) — delegated to TaskFilter
  # ---------------------------------------------------------------------------

  def parse_due_date_filter(value), do: TaskFilter.parse_due_date_filter(value)

  def parse_activity_filter(value), do: TaskFilter.parse_activity_filter(value)

  def state_dot_color(color) when is_binary(color), do: color
  def state_dot_color(_), do: "#6B7280"

  # ---------------------------------------------------------------------------
  # Task loading
  # ---------------------------------------------------------------------------

  def load_tasks(socket) do
    project_id = socket.assigns.project_id
    query = socket.assigns.search_query
    show_archived = socket.assigns.show_archived
    show_completed = socket.assigns.show_completed

    all_tasks =
      if String.length(String.trim(query)) >= 4 do
        EyeInTheSky.Tasks.search_tasks(query, project_id)
      else
        EyeInTheSky.Tasks.list_tasks_for_project(project_id, include_archived: show_archived)
      end
      |> then(fn tasks ->
        if show_completed, do: tasks, else: Enum.reject(tasks, & &1.completed_at)
      end)
      |> EyeInTheSky.Notes.with_notes_count()

    all_tag_refs = Enum.flat_map(all_tasks, fn t -> t.tags || [] end)

    available_tags =
      all_tag_refs
      |> Enum.uniq_by(& &1.name)
      |> Enum.sort_by(& &1.name)

    tag_counts = Enum.frequencies_by(all_tag_refs, & &1.name)

    socket
    |> assign(:tasks, all_tasks)
    |> assign(:available_tags, available_tags)
    |> assign(:tag_counts, tag_counts)
    |> apply_filters()
  end

end
