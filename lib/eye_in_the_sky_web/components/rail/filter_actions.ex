defmodule EyeInTheSkyWeb.Components.Rail.FilterActions do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSkyWeb.Components.Rail.Loader

  def handle_set_session_sort(%{"sort" => sort_str}, socket) do
    sort = Loader.parse_session_sort(sort_str)

    sessions =
      Loader.load_flyout_sessions(
        socket.assigns.sidebar_project,
        sort,
        socket.assigns.session_name_filter
      )

    {:noreply, socket |> assign(:session_sort, sort) |> assign(:flyout_sessions, sessions)}
  end

  def handle_update_session_name_filter(%{"value" => value}, socket) do
    sessions =
      Loader.load_flyout_sessions(
        socket.assigns.sidebar_project,
        socket.assigns.session_sort,
        value
      )

    {:noreply, socket |> assign(:session_name_filter, value) |> assign(:flyout_sessions, sessions)}
  end

  def handle_update_task_search(%{"value" => value}, socket) do
    tasks =
      Loader.load_flyout_tasks(
        socket.assigns.sidebar_project,
        value,
        socket.assigns.task_state_filter
      )

    {:noreply, socket |> assign(:task_search, value) |> assign(:flyout_tasks, tasks)}
  end

  def handle_set_task_state_filter(%{"state" => state_str}, socket) do
    state_id = Loader.parse_task_state(state_str)

    tasks =
      Loader.load_flyout_tasks(
        socket.assigns.sidebar_project,
        socket.assigns.task_search,
        state_id
      )

    {:noreply, socket |> assign(:task_state_filter, state_id) |> assign(:flyout_tasks, tasks)}
  end
end
