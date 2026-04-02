defmodule EyeInTheSkyWeb.OverviewLive.Tasks do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Tasks

  alias EyeInTheSkyWeb.Components.FilterSheet
  alias EyeInTheSkyWeb.Components.TaskCard
  import EyeInTheSkyWeb.Live.Shared.TasksHelpers

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_tasks()
    end

    workflow_states = Tasks.list_workflow_states()

    socket =
      socket
      |> assign(:page_title, "All Tasks")
      |> assign(:search_query, "")
      |> assign(:workflow_states, workflow_states)
      |> assign(:filter_state_id, nil)
      |> assign(:sort_by, "created_desc")
      |> assign(:task_count, 0)
      |> assign(:page, 1)
      |> assign(:has_more, false)
      |> assign(:total_tasks, 0)
      |> assign(:sidebar_tab, :tasks)
      |> stream(:tasks, [], dom_id: fn t -> "ot-#{t.id}" end)
      |> assign(:sidebar_project, nil)
      |> assign(:show_filter_sheet, false)
      |> assign(:show_task_detail_drawer, false)
      |> assign(:selected_task, nil)
      |> assign(:task_notes, [])
      |> assign(:show_create_task_drawer, false)
      |> load_tasks()

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"intent" => "create"}, _uri, socket) do
    {:noreply, assign(socket, :show_create_task_drawer, true)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", params, socket),
    do: handle_search(params, socket, &load_tasks/1)

  @impl true
  def handle_event("filter_status", %{"state_id" => state_id}, socket) do
    state_id = if state_id == "", do: nil, else: String.to_integer(state_id)

    {:noreply,
     socket
     |> assign(:filter_state_id, state_id)
     |> load_tasks()}
  end

  @impl true
  def handle_event("sort_by", %{"value" => value}, socket) do
    {:noreply, socket |> assign(:sort_by, value) |> load_tasks()}
  end

  @impl true
  def handle_event("open_filter_sheet", params, socket),
    do: handle_open_filter_sheet(params, socket)

  @impl true
  def handle_event("close_filter_sheet", params, socket),
    do: handle_close_filter_sheet(params, socket)

  @impl true
  def handle_event("load_more", params, socket),
    do: handle_load_more(params, socket, &load_tasks_page/2)

  @impl true
  def handle_event("open_task_detail", params, socket),
    do: handle_open_task_detail(params, socket)

  @impl true
  def handle_event("toggle_task_detail_drawer", params, socket),
    do: handle_toggle_task_detail_drawer(params, socket)

  @impl true
  def handle_event("update_task", params, socket),
    do: handle_update_task(params, socket, &load_tasks/1)

  @impl true
  def handle_event("delete_task", params, socket),
    do: handle_delete_task(params, socket, &load_tasks/1)

  @impl true
  def handle_event("start_agent_for_task", _params, socket) do
    {:noreply, put_flash(socket, :info, "Open the project Kanban board to start agents")}
  end

  @impl true
  def handle_event("toggle_create_task_drawer", _params, socket) do
    {:noreply, assign(socket, :show_create_task_drawer, !socket.assigns.show_create_task_drawer)}
  end

  @impl true
  def handle_event("create_new_task", params, socket),
    do: handle_create_new_task(params, socket, &load_tasks/1)

  @impl true
  def handle_info(:tasks_changed, socket),
    do: handle_tasks_changed(socket, &load_tasks/1)

  # Resets to page 1, replaces the task list
  defp load_tasks(socket) do
    query = socket.assigns.search_query
    state_id = socket.assigns.filter_state_id
    sort_by = socket.assigns.sort_by

    if query != "" and String.trim(query) != "" do
      tasks = Tasks.search_tasks(query)

      tasks =
        if state_id,
          do: Enum.filter(tasks, &(&1.state_id == state_id)),
          else: tasks

      socket
      |> assign(:task_count, length(tasks))
      |> assign(:page, 1)
      |> assign(:has_more, false)
      |> assign(:total_tasks, length(tasks))
      |> stream(:tasks, tasks, reset: true)
    else
      total = Tasks.count_tasks(state_id: state_id)
      tasks = Tasks.list_tasks(limit: @per_page, offset: 0, state_id: state_id, sort_by: sort_by)

      socket
      |> assign(:task_count, length(tasks))
      |> assign(:page, 1)
      |> assign(:has_more, length(tasks) < total)
      |> assign(:total_tasks, total)
      |> stream(:tasks, tasks, reset: true)
    end
  end

  # Appends the next page to the existing task list
  defp load_tasks_page(socket, page) do
    state_id = socket.assigns.filter_state_id
    sort_by = socket.assigns.sort_by
    offset = (page - 1) * @per_page
    total = socket.assigns.total_tasks

    new_tasks = Tasks.list_tasks(limit: @per_page, offset: offset, state_id: state_id, sort_by: sort_by)

    socket =
      socket
      |> update(:task_count, &(&1 + length(new_tasks)))
      |> assign(:page, page)
      |> assign(:has_more, offset + length(new_tasks) < total)

    Enum.reduce(new_tasks, socket, fn task, acc ->
      stream_insert(acc, :tasks, task)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="max-w-4xl mx-auto">
        <%!-- Search + State filters --%>
        <div class="mb-5 flex items-center gap-3">
          <form phx-change="search" class="flex-1 sm:max-w-sm">
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
              </div>
              <label for="overview-tasks-search" class="sr-only">Search tasks</label>
              <input
                type="text"
                name="query"
                id="overview-tasks-search"
                value={@search_query}
                placeholder="Search tasks..."
                class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm"
                autocomplete="off"
              />
            </div>
          </form>

          <button
            phx-click="toggle_create_task_drawer"
            class="btn btn-sm btn-primary gap-1.5 min-h-0 h-8 text-xs"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Task
          </button>

          <%!-- Mobile filter button --%>
          <button
            phx-click="open_filter_sheet"
            aria-label="Open filters"
            aria-haspopup="dialog"
            class="sm:hidden relative btn btn-ghost btn-sm btn-square"
          >
            <.icon name="hero-funnel-mini" class="w-4 h-4" />
            <%= if !is_nil(@filter_state_id) || @sort_by != "created_desc" do %>
              <span
                class="absolute top-0.5 right-0.5 w-2 h-2 bg-primary rounded-full"
                aria-hidden="true"
              >
              </span>
            <% end %>
          </button>

          <%!-- Desktop filter pills --%>
          <div class="hidden sm:flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
            <button
              phx-click="filter_status"
              phx-value-state_id=""
              aria-pressed={is_nil(@filter_state_id)}
              class={"px-3 py-1.5 rounded-md text-xs font-medium transition-all duration-150 " <>
                if(is_nil(@filter_state_id),
                  do: "bg-base-100 text-base-content shadow-sm",
                  else: "text-base-content/60 hover:text-base-content/85"
                )}
            >
              All
            </button>
            <button
              :for={state <- @workflow_states}
              phx-click="filter_status"
              phx-value-state_id={state.id}
              aria-pressed={@filter_state_id == state.id}
              class={"px-3 py-1.5 rounded-md text-xs font-medium transition-all duration-150 " <>
                if(@filter_state_id == state.id,
                  do: "bg-base-100 text-base-content shadow-sm",
                  else: "text-base-content/60 hover:text-base-content/85"
                )}
            >
              {state.name}
            </button>
          </div>

          <%!-- Desktop sort dropdown --%>
          <form phx-change="sort_by" class="hidden sm:block">
            <label for="overview-tasks-sort" class="sr-only">Sort tasks</label>
            <select
              name="value"
              id="overview-tasks-sort"
              class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-0 h-8 text-xs"
            >
              <option value="created_desc" selected={@sort_by == "created_desc"}>Newest first</option>
              <option value="created_asc" selected={@sort_by == "created_asc"}>Oldest first</option>
              <option value="priority" selected={@sort_by == "priority"}>Priority</option>
            </select>
          </form>
        </div>

        <%!-- Mobile filter bottom sheet --%>
        <FilterSheet.filter_sheet
          id="overview-tasks-filter-sheet"
          show={@show_filter_sheet}
          title="Filter & Sort"
          workflow_states={@workflow_states}
          filter_state_id={@filter_state_id}
          show_sort={true}
          sort_by={@sort_by}
        />

        <%!-- Task count --%>
        <div class="mb-3">
          <span class="text-[11px] font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
            <%= if @has_more do %>
              {@task_count} of {@total_tasks} tasks
            <% else %>
              {@total_tasks} tasks
            <% end %>
          </span>
        </div>

        <%= if @task_count > 0 do %>
          <div
            id="overview-tasks-list"
            phx-update="stream"
            class="divide-y divide-base-content/5 bg-base-100 rounded-xl shadow-sm px-5"
          >
            <div :for={{dom_id, task} <- @streams.tasks} id={dom_id}>
              <TaskCard.task_card
                task={task}
                variant="list"
                on_click="open_task_detail"
                on_delete="delete_task"
              />
            </div>
          </div>

          <div
            id="overview-tasks-sentinel"
            phx-hook="InfiniteScroll"
            data-has-more={to_string(@has_more)}
            data-page={@page}
            class="py-4 flex justify-center"
          >
            <%= if @has_more do %>
              <span class="loading loading-spinner loading-sm text-base-content/30"></span>
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="overview-tasks-empty"
            icon="hero-clipboard-document-list"
            title={
              if @search_query != "" || !is_nil(@filter_state_id),
                do: "No tasks found",
                else: "No tasks yet"
            }
            subtitle={
              if @search_query != "" || !is_nil(@filter_state_id),
                do: "Try adjusting your search or filters",
                else: "Tasks created by agents will appear here"
            }
          />
        <% end %>
      </div>
    </div>

    <!-- New Task Drawer -->
    <EyeInTheSkyWeb.Components.NewTaskDrawer.new_task_drawer
      id="tasks-new-task-drawer"
      show={@show_create_task_drawer}
      workflow_states={@workflow_states}
      toggle_event="toggle_create_task_drawer"
      submit_event="create_new_task"
    />

    <!-- Task Detail Drawer -->
    <EyeInTheSkyWeb.Components.TaskDetailDrawer.task_detail_drawer
      id="task-detail-drawer"
      show={@show_task_detail_drawer}
      task={@selected_task}
      notes={@task_notes}
      workflow_states={@workflow_states}
      toggle_event="toggle_task_detail_drawer"
      update_event="update_task"
      delete_event="delete_task"
    />
    """
  end
end
