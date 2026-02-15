defmodule EyeInTheSkyWebWeb.OverviewLive.Tasks do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Tasks
  alias EyeInTheSkyWebWeb.Components.TaskCard

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks")
    end

    workflow_states = Tasks.list_workflow_states()

    socket =
      socket
      |> assign(:page_title, "All Tasks")
      |> assign(:search_query, "")
      |> assign(:workflow_states, workflow_states)
      |> assign(:state_filter, "all")
      |> assign(:tasks, [])
      |> assign(:sidebar_tab, :tasks)
      |> assign(:sidebar_project, nil)
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

  @impl true
  def handle_info(:tasks_changed, socket) do
    {:noreply, load_tasks(socket)}
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
        "all" ->
          tasks

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
    <div class="px-6 lg:px-8 py-6">
      <div class="max-w-4xl mx-auto">
        <%!-- Search + State filters --%>
        <div class="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center">
          <form phx-change="search" class="flex-1 max-w-sm">
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
              </div>
              <input
                type="text"
                name="query"
                value={@search_query}
                placeholder="Search tasks..."
                class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm"
                autocomplete="off"
              />
            </div>
          </form>

          <div class="flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
            <button
              phx-click="filter_state"
              phx-value-state="all"
              class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                if(@state_filter == "all",
                  do: "bg-base-100 text-base-content shadow-sm",
                  else: "text-base-content/40 hover:text-base-content/60"
                )}
            >
              All
            </button>
            <%= for state <- @workflow_states do %>
              <button
                phx-click="filter_state"
                phx-value-state={to_string(state.id)}
                class={"px-3 py-1 rounded-md text-xs font-medium transition-all duration-150 " <>
                  if(@state_filter == to_string(state.id),
                    do: "bg-base-100 text-base-content shadow-sm",
                    else: "text-base-content/40 hover:text-base-content/60"
                  )}
              >
                {state.name}
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Task count --%>
        <div class="mb-3">
          <span class="text-[11px] font-mono tabular-nums text-base-content/30 tracking-wider uppercase">
            {length(@tasks)} tasks
          </span>
        </div>

        <%= if length(@tasks) > 0 do %>
          <div class="divide-y divide-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm px-5">
            <%= for task <- @tasks do %>
              <TaskCard.task_card task={task} variant="list" />
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="overview-tasks-empty"
            icon="hero-clipboard-document-list"
            title={if @search_query != "" || @state_filter != "all", do: "No tasks found", else: "No tasks yet"}
            subtitle={if @search_query != "" || @state_filter != "all", do: "Try adjusting your search or filters", else: "Tasks created by agents will appear here"}
          />
        <% end %>
      </div>
    </div>
    """
  end
end
