defmodule EyeInTheSkyWebWeb.OverviewLive.Tasks do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Tasks
  alias EyeInTheSkyWebWeb.Components.TaskCard

  @impl true
  def mount(_params, _session, socket) do
    workflow_states = Tasks.list_workflow_states()

    socket =
      socket
      |> assign(:page_title, "All Tasks")
      |> assign(:search_query, "")
      |> assign(:workflow_states, workflow_states)
      |> assign(:state_filter, "all")
      |> assign(:tasks, [])
      |> load_tasks()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 4, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> load_tasks()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_state", %{"state" => state}, socket) do
    socket =
      socket
      |> assign(:state_filter, state)
      |> load_tasks()

    {:noreply, socket}
  end

  defp load_tasks(socket) do
    query = socket.assigns.search_query
    state_filter = socket.assigns.state_filter

    tasks =
      if query != "" and String.trim(query) != "" do
        Tasks.search_tasks(query)
      else
        Tasks.list_tasks()
      end

    tasks =
      case state_filter do
        "all" -> tasks
        state_id_str ->
          case Integer.parse(state_id_str) do
            {state_id, ""} -> Enum.filter(tasks, &(&1.state_id == state_id))
            _ -> tasks
          end
      end

    assign(socket, :tasks, tasks)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_component module={EyeInTheSkyWebWeb.Components.Navbar} id="navbar" />
    <EyeInTheSkyWebWeb.Components.OverviewNav.render current_tab={:tasks} />

    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="flex items-center gap-4 max-w-4xl">
        <form phx-change="search" class="flex-1">
          <input
            type="text"
            name="query"
            value={@search_query}
            placeholder="Search tasks by title or description..."
            class="input input-bordered w-full"
            autocomplete="off"
          />
        </form>
        <!-- State filter -->
        <div class="btn-group">
          <button
            phx-click="filter_state"
            phx-value-state="all"
            class={"btn btn-sm #{if @state_filter == "all", do: "btn-active"}"}
          >
            All
          </button>
          <%= for state <- @workflow_states do %>
            <button
              phx-click="filter_state"
              phx-value-state={to_string(state.id)}
              class={"btn btn-sm #{if @state_filter == to_string(state.id), do: "btn-active"}"}
            >
              {state.name}
            </button>
          <% end %>
        </div>
      </div>
    </div>

    <div class="px-4 sm:px-6 lg:px-8 pb-8">
      <%= if length(@tasks) > 0 do %>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          <%= for task <- @tasks do %>
            <TaskCard.task_card task={task} variant="grid" />
          <% end %>
        </div>
      <% else %>
        <div class="text-center py-16">
          <div class="mx-auto w-24 h-24 bg-base-200 rounded-full flex items-center justify-center mb-4">
            <svg
              class="w-12 h-12 text-base-content/40"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
              />
            </svg>
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2">
            <%= if @search_query != "" do %>
              No tasks found
            <% else %>
              No tasks yet
            <% end %>
          </h3>
          <p class="text-sm text-base-content/60">
            <%= if @search_query != "" do %>
              Try adjusting your search query
            <% else %>
              Tasks created by agents will appear here
            <% end %>
          </p>
        </div>
      <% end %>
    </div>
    """
  end
end
