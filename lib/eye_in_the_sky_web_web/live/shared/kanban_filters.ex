defmodule EyeInTheSkyWebWeb.Live.Shared.KanbanFilters do
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

  # ---------------------------------------------------------------------------
  # Private filter implementations
  # ---------------------------------------------------------------------------

  defp filter_by_priority(tasks, nil), do: tasks
  defp filter_by_priority(tasks, priority), do: Enum.filter(tasks, &(&1.priority == priority))

  defp filter_by_tags(tasks, %MapSet{} = tags, mode) do
    if MapSet.size(tags) == 0 do
      tasks
    else
      Enum.filter(tasks, fn t ->
        task_tag_names = MapSet.new(t.tags || [], & &1.name)

        case mode do
          :and -> MapSet.subset?(tags, task_tag_names)
          :or -> MapSet.size(MapSet.intersection(tags, task_tag_names)) > 0
        end
      end)
    end
  end

  defp filter_by_due_date(tasks, nil), do: tasks
  defp filter_by_due_date(tasks, :no_date), do: Enum.filter(tasks, &is_nil(&1.due_at))

  defp filter_by_due_date(tasks, filter) do
    today = Date.utc_today()

    Enum.filter(tasks, fn task ->
      case task.due_at do
        nil ->
          false

        due_str ->
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
    end)
  end

  defp filter_by_activity(tasks, nil), do: tasks

  defp filter_by_activity(tasks, filter) do
    now = DateTime.utc_now()

    Enum.filter(tasks, fn task ->
      days_ago =
        case task.updated_at do
          nil ->
            999

          str ->
            case DateTime.from_iso8601(str) do
              {:ok, dt, _} -> DateTime.diff(now, dt, :second) |> div(86400)
              _ -> 999
            end
        end

      case filter do
        :week -> days_ago <= 7
        :two_weeks -> days_ago <= 14
        :four_weeks -> days_ago <= 28
        :inactive -> days_ago > 28
        _ -> true
      end
    end)
  end
end
