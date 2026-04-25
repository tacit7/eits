defmodule EyeInTheSkyWeb.ProjectLive.Sessions.FilterHandlers do
  @moduledoc """
  Handles search/filter/sort/pagination and drawer-toggle events for the
  project sessions LiveView.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream_insert: 3]

  alias EyeInTheSkyWeb.ProjectLive.Sessions.Loader
  alias EyeInTheSkyWeb.ProjectLive.Sessions.State

  def search(%{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 3, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> Loader.apply_agent_view(true)

    {:noreply, socket}
  end

  def filter_session(%{"filter" => filter}, socket) do
    socket =
      socket
      |> assign(:session_filter, filter)
      |> assign(:selected_ids, MapSet.new())
      |> assign(:select_mode, false)
      |> Loader.load_agents()

    {:noreply, socket}
  end

  def sort(%{"by" => sort_by}, socket) do
    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> Loader.apply_agent_view(true)

    {:noreply, socket}
  end

  def load_more(_params, socket) do
    if socket.assigns.has_more do
      old_count = socket.assigns.visible_count
      new_count = old_count + State.page_size()
      agents = socket.assigns.agents

      new_items = Enum.slice(agents, old_count, State.page_size())

      socket =
        socket
        |> assign(:visible_count, new_count)
        |> assign(:has_more, length(agents) > new_count)

      socket =
        Enum.reduce(new_items, socket, fn agent, acc ->
          stream_insert(acc, :session_list, agent)
        end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def open_filter_sheet(_params, socket) do
    {:noreply, assign(socket, :show_filter_sheet, true)}
  end

  def close_filter_sheet(_params, socket) do
    {:noreply, assign(socket, :show_filter_sheet, false)}
  end

  def toggle_new_session_drawer(_params, socket) do
    {:noreply, assign(socket, :show_new_session_drawer, !socket.assigns.show_new_session_drawer)}
  end
end
