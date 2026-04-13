defmodule EyeInTheSkyWeb.Live.Shared.KanbanFilters do
  @moduledoc """
  Filter logic for the kanban board.

  Extracted from Kanban LiveView to keep the board focused on
  mount, event routing, and rendering.
  """

  import Phoenix.Component, only: [assign: 3]

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
      |> filter_by_priority(priority_filter)
      |> filter_by_tags(filter_tags, tag_mode)
      |> filter_by_due_date(filter_due_date)
      |> filter_by_activity(filter_activity)

    tasks_by_state =
      Enum.group_by(filtered, fn task ->
        if task.state, do: task.state.id, else: nil
      end)

    assign(socket, :tasks_by_state, tasks_by_state)
  end

  # ---------------------------------------------------------------------------
  # Filter parsers (string value → atom)
  # ---------------------------------------------------------------------------

  def parse_due_date_filter("no_date"), do: :no_date
  def parse_due_date_filter("overdue"), do: :overdue
  def parse_due_date_filter("next_day"), do: :next_day
  def parse_due_date_filter("next_week"), do: :next_week
  def parse_due_date_filter("next_month"), do: :next_month
  def parse_due_date_filter(_), do: nil

  def parse_activity_filter("week"), do: :week
  def parse_activity_filter("two_weeks"), do: :two_weeks
  def parse_activity_filter("four_weeks"), do: :four_weeks
  def parse_activity_filter("inactive"), do: :inactive
  def parse_activity_filter(_), do: nil

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

  # ---------------------------------------------------------------------------
  # Private filter implementations
  # ---------------------------------------------------------------------------

  defp filter_by_priority(tasks, nil), do: tasks
  defp filter_by_priority(tasks, priority), do: Enum.filter(tasks, &(&1.priority == priority))

  defp filter_by_tags(tasks, %MapSet{} = tags, mode) do
    if MapSet.size(tags) == 0 do
      tasks
    else
      Enum.filter(tasks, &task_matches_tags?(&1, tags, mode))
    end
  end

  defp task_matches_tags?(t, tags, mode) do
    task_tag_names = MapSet.new(t.tags || [], & &1.name)

    case mode do
      :and -> MapSet.subset?(tags, task_tag_names)
      :or -> MapSet.size(MapSet.intersection(tags, task_tag_names)) > 0
    end
  end

  defp filter_by_due_date(tasks, nil), do: tasks
  defp filter_by_due_date(tasks, :no_date), do: Enum.filter(tasks, &is_nil(&1.due_at))

  defp filter_by_due_date(tasks, filter) do
    today = Date.utc_today()
    Enum.filter(tasks, &task_matches_due_date?(&1, filter, today))
  end

  defp task_matches_due_date?(task, filter, today) do
    case task.due_at do
      nil -> false
      due_str -> check_due_date(due_str, filter, today)
    end
  end

  defp check_due_date(due_str, filter, today) do
    case Date.from_iso8601(String.slice(due_str, 0, 10)) do
      {:ok, due} ->
        case filter do
          :overdue -> Date.compare(due, today) == :lt
          :next_day -> Date.compare(due, today) != :lt && Date.diff(due, today) <= 1
          :next_week -> Date.compare(due, today) != :lt && Date.diff(due, today) <= 7
          :next_month -> Date.compare(due, today) != :lt && Date.diff(due, today) <= 30
          _ -> true
        end

      _ ->
        false
    end
  end

  defp filter_by_activity(tasks, nil), do: tasks

  defp filter_by_activity(tasks, filter) do
    now = DateTime.utc_now()
    Enum.filter(tasks, &task_matches_activity?(&1, filter, now))
  end

  defp task_matches_activity?(task, filter, now) do
    days_ago = task_days_ago(task.updated_at, now)

    case filter do
      :week -> days_ago <= 7
      :two_weeks -> days_ago <= 14
      :four_weeks -> days_ago <= 28
      :inactive -> days_ago > 28
      _ -> true
    end
  end

  defp task_days_ago(nil, _now), do: 999

  defp task_days_ago(str, now) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.diff(now, dt, :second) |> div(86_400)
      _ -> 999
    end
  end
end
