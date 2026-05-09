defmodule EyeInTheSky.TaskFilter do
  @moduledoc """
  Pure, context-level filter functions for tasks.

  Independently testable predicates and filters used by the kanban board
  and other views. All functions are pure with no side effects.
  """

  # ---------------------------------------------------------------------------
  # Filter by priority
  # ---------------------------------------------------------------------------

  @doc """
  Filter tasks by priority.

  Returns all tasks if priority is nil.
  """
  def filter_by_priority(tasks, nil), do: tasks
  def filter_by_priority(tasks, priority), do: Enum.filter(tasks, &(&1.priority == priority))

  # ---------------------------------------------------------------------------
  # Filter by tags
  # ---------------------------------------------------------------------------

  @doc """
  Filter tasks by tags with AND or OR mode.

  If no tags are selected, returns all tasks.
  - `:and` mode: task must have ALL selected tags
  - `:or` mode: task must have AT LEAST ONE selected tag
  """
  def filter_by_tags(tasks, %MapSet{} = tags, mode) do
    if MapSet.size(tags) == 0 do
      tasks
    else
      Enum.filter(tasks, &task_matches_tags?(&1, tags, mode))
    end
  end

  @doc """
  Check if a task matches the given tags in the given mode.
  """
  def task_matches_tags?(t, tags, mode) do
    task_tag_names = MapSet.new(t.tags || [], & &1.name)

    case mode do
      :and -> MapSet.subset?(tags, task_tag_names)
      :or -> MapSet.size(MapSet.intersection(tags, task_tag_names)) > 0
    end
  end

  # ---------------------------------------------------------------------------
  # Filter by due date
  # ---------------------------------------------------------------------------

  @doc """
  Filter tasks by due date filter type.

  Returns all tasks if filter is nil. Supports:
  - `:no_date` — tasks with no due date
  - `:overdue` — due date is before today
  - `:next_day` — due within 1 day
  - `:next_week` — due within 7 days
  - `:next_month` — due within 30 days
  """
  def filter_by_due_date(tasks, nil), do: tasks
  def filter_by_due_date(tasks, :no_date), do: Enum.filter(tasks, &is_nil(&1.due_at))

  def filter_by_due_date(tasks, filter) do
    today = Date.utc_today()
    Enum.filter(tasks, &task_matches_due_date?(&1, filter, today))
  end

  @doc """
  Check if a task matches the given due date filter against today.
  """
  def task_matches_due_date?(task, filter, today) do
    case task.due_at do
      nil -> false
      due_str -> check_due_date(due_str, filter, today)
    end
  end

  @doc """
  Check a task's due date string against a filter type and reference date.
  """
  def check_due_date(due_str, filter, today) do
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

  # ---------------------------------------------------------------------------
  # Filter by activity
  # ---------------------------------------------------------------------------

  @doc """
  Filter tasks by activity level (days since last update).

  Returns all tasks if filter is nil. Supports:
  - `:week` — updated within 7 days
  - `:two_weeks` — updated within 14 days
  - `:four_weeks` — updated within 28 days
  - `:inactive` — not updated for 28+ days
  """
  def filter_by_activity(tasks, nil), do: tasks

  def filter_by_activity(tasks, filter) do
    now = DateTime.utc_now()
    Enum.filter(tasks, &task_matches_activity?(&1, filter, now))
  end

  @doc """
  Check if a task matches the given activity filter against now.
  """
  def task_matches_activity?(task, filter, now) do
    days_ago = task_days_ago(task.updated_at, now)

    case filter do
      :week -> days_ago <= 7
      :two_weeks -> days_ago <= 14
      :four_weeks -> days_ago <= 28
      :inactive -> days_ago > 28
      _ -> true
    end
  end

  @doc """
  Calculate days since task.updated_at (ISO8601 string) until now.

  Returns 999 if nil or unparseable (treated as very old).
  """
  def task_days_ago(nil, _now), do: 999

  def task_days_ago(str, now) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.diff(now, dt, :second) |> div(86_400)
      _ -> 999
    end
  end

  # ---------------------------------------------------------------------------
  # Filter string parsers (for form inputs)
  # ---------------------------------------------------------------------------

  @doc """
  Parse a due date filter string into an atom or nil.
  """
  def parse_due_date_filter("no_date"), do: :no_date
  def parse_due_date_filter("overdue"), do: :overdue
  def parse_due_date_filter("next_day"), do: :next_day
  def parse_due_date_filter("next_week"), do: :next_week
  def parse_due_date_filter("next_month"), do: :next_month
  def parse_due_date_filter(_), do: nil

  @doc """
  Parse an activity filter string into an atom or nil.
  """
  def parse_activity_filter("week"), do: :week
  def parse_activity_filter("two_weeks"), do: :two_weeks
  def parse_activity_filter("four_weeks"), do: :four_weeks
  def parse_activity_filter("inactive"), do: :inactive
  def parse_activity_filter(_), do: nil
end
