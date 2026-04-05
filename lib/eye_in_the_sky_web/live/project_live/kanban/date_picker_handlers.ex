defmodule EyeInTheSkyWeb.ProjectLive.Kanban.DatePickerHandlers do
  @moduledoc """
  Date picker event handlers for the Kanban LiveView.

  All handlers return {:noreply, socket} tuples.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSkyWeb.Live.Shared.KanbanFilters

  def handle_open_date_picker(%{"task_id" => task_id}, socket) do
    task = EyeInTheSky.Tasks.get_task_by_uuid_or_id!(task_id)
    today = Date.utc_today()

    selected =
      case task.due_at do
        nil -> nil
        dt -> dt |> DateTime.to_date() |> Date.to_iso8601()
      end

    {year, month} =
      case task.due_at do
        nil ->
          {today.year, today.month}

        dt ->
          dt = DateTime.to_date(dt)
          {dt.year, dt.month}
      end

    {:noreply,
     socket
     |> assign(:show_date_picker, true)
     |> assign(:date_picker_task, task)
     |> assign(:date_picker_year, year)
     |> assign(:date_picker_month, month)
     |> assign(:date_picker_selected, selected)}
  end

  def handle_close_date_picker(socket) do
    {:noreply, assign(socket, :show_date_picker, false)}
  end

  def handle_date_picker_prev_month(socket) do
    {year, month} = prev_month(socket.assigns.date_picker_year, socket.assigns.date_picker_month)
    {:noreply, socket |> assign(:date_picker_year, year) |> assign(:date_picker_month, month)}
  end

  def handle_date_picker_next_month(socket) do
    {year, month} = next_month(socket.assigns.date_picker_year, socket.assigns.date_picker_month)
    {:noreply, socket |> assign(:date_picker_year, year) |> assign(:date_picker_month, month)}
  end

  def handle_select_due_date(%{"date" => date_str}, socket) do
    {:noreply, assign(socket, :date_picker_selected, date_str)}
  end

  def handle_save_due_date(%{"task_id" => task_id, "due_at" => due_at_str}, socket) do
    task = EyeInTheSky.Tasks.get_task_by_uuid_or_id!(task_id)
    due_at = if due_at_str == "", do: nil, else: due_at_str

    case EyeInTheSky.Tasks.update_task(task, %{due_at: due_at, updated_at: DateTime.utc_now()}) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:show_date_picker, false)
         |> KanbanFilters.load_tasks()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update due date")}
    end
  end

  def handle_remove_due_date(%{"task_id" => task_id}, socket) do
    task = EyeInTheSky.Tasks.get_task_by_uuid_or_id!(task_id)

    case EyeInTheSky.Tasks.update_task(task, %{due_at: nil, updated_at: DateTime.utc_now()}) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:show_date_picker, false)
         |> KanbanFilters.load_tasks()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove due date")}
    end
  end

  defp prev_month(year, 1), do: {year - 1, 12}
  defp prev_month(year, month), do: {year, month - 1}

  defp next_month(year, 12), do: {year + 1, 1}
  defp next_month(year, month), do: {year, month + 1}
end
