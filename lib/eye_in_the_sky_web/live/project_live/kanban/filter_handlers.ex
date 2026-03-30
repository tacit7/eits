defmodule EyeInTheSkyWeb.ProjectLive.Kanban.FilterHandlers do
  @moduledoc """
  Filter event handlers for the Kanban LiveView.

  All handlers return {:noreply, socket} tuples and delegate
  filter logic to KanbanFilters.
  """

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.Live.Shared.KanbanFilters

  def handle_clear_filters(socket) do
    {:noreply,
     socket
     |> assign(:filter_priority, nil)
     |> assign(:filter_tags, MapSet.new())
     |> assign(:filter_tag_mode, :and)
     |> assign(:filter_due_date, nil)
     |> assign(:filter_activity, nil)
     |> KanbanFilters.apply_filters()}
  end

  def handle_toggle_filter_drawer(socket) do
    {:noreply, assign(socket, :show_filter_drawer, !socket.assigns.show_filter_drawer)}
  end

  def handle_update_filter(%{"field" => "due_date", "value" => value}, socket) do
    new_val = KanbanFilters.parse_due_date_filter(value)
    current = socket.assigns.filter_due_date
    filter = if current == new_val, do: nil, else: new_val
    {:noreply, socket |> assign(:filter_due_date, filter) |> KanbanFilters.apply_filters()}
  end

  def handle_update_filter(%{"field" => "activity", "value" => value}, socket) do
    new_val = KanbanFilters.parse_activity_filter(value)
    current = socket.assigns.filter_activity
    filter = if current == new_val, do: nil, else: new_val
    {:noreply, socket |> assign(:filter_activity, filter) |> KanbanFilters.apply_filters()}
  end

  def handle_update_filter(%{"field" => "priority", "value" => priority}, socket) do
    new_priority = case Integer.parse(priority) do
      {int, ""} -> int
      :error -> nil
    end
    current = socket.assigns.filter_priority
    priority_filter = if current == new_priority, do: nil, else: new_priority
    {:noreply, socket |> assign(:filter_priority, priority_filter) |> KanbanFilters.apply_filters()}
  end

  def handle_update_filter(%{"field" => "tag", "value" => tag}, socket) do
    current_tags = socket.assigns.filter_tags

    updated_tags =
      if MapSet.member?(current_tags, tag),
        do: MapSet.delete(current_tags, tag),
        else: MapSet.put(current_tags, tag)

    {:noreply, socket |> assign(:filter_tags, updated_tags) |> KanbanFilters.apply_filters()}
  end

  def handle_update_filter(%{"field" => "tag_mode", "value" => mode}, socket) do
    new_mode = if mode == "or", do: :or, else: :and
    {:noreply, socket |> assign(:filter_tag_mode, new_mode) |> KanbanFilters.apply_filters()}
  end

  def handle_update_filter(_params, socket), do: {:noreply, socket}

  def handle_toggle_filters(socket) do
    {:noreply, assign(socket, :show_filters, !socket.assigns.show_filters)}
  end

  def handle_toggle_show_completed(socket) do
    {:noreply,
     socket |> assign(:show_completed, !socket.assigns.show_completed) |> KanbanFilters.load_tasks()}
  end

  def handle_toggle_show_archived(socket) do
    {:noreply,
     socket |> assign(:show_archived, !socket.assigns.show_archived) |> KanbanFilters.load_tasks()}
  end
end
