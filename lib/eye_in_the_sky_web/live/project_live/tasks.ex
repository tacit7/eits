defmodule EyeInTheSkyWeb.ProjectLive.Tasks do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Tasks
  alias EyeInTheSkyWeb.Components.FilterSheet
  alias EyeInTheSkyWeb.Components.TaskCard
  alias EyeInTheSkyWeb.ControllerHelpers
  alias EyeInTheSkyWeb.Live.Shared.TasksListHelpers
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWeb.Live.Shared.TasksHelpers

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    if connected?(socket), do: subscribe_tasks()

    workflow_states = Tasks.list_workflow_states()

    socket =
      socket
      |> mount_project(params,
        sidebar_tab: :tasks,
        page_title_prefix: "Tasks",
        preload: [:agents]
      )
      |> assign(:search_query, "")
      |> assign(:filter_state_id, nil)
      |> assign(:sort_by, "created_desc")
      |> assign(:workflow_states, workflow_states)
      |> assign(:show_new_task_drawer, false)
      |> assign(:show_filter_sheet, false)
      |> assign(:show_task_detail_drawer, false)
      |> assign(:selected_task, nil)
      |> assign(:task_notes, [])
      |> assign(:task_count, 0)
      |> assign(:page, 1)
      |> assign(:has_more, false)
      |> assign(:total_tasks, 0)
      |> stream(:tasks, [], dom_id: fn t -> "pt-#{t.id}" end)

    socket = if socket.assigns.project, do: load_tasks(socket), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("search", params, socket),
    do: handle_search(params, socket, &load_tasks/1)

  @impl true
  def handle_event("filter_status", %{"state_id" => state_id}, socket) do
    state_id = if state_id == "", do: nil, else: ControllerHelpers.parse_int(state_id)

    {:noreply,
     socket
     |> assign(:filter_state_id, state_id)
     |> load_tasks()}
  end

  @impl true
  def handle_event("sort_by", %{"value" => value}, socket) do
    {:noreply,
     socket
     |> assign(:sort_by, value)
     |> load_tasks()}
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
  def handle_event("toggle_new_task_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_task_drawer, !socket.assigns.show_new_task_drawer)}
  end

  @impl true
  def handle_event("toggle_task_detail_drawer", params, socket),
    do: handle_toggle_task_detail_drawer(params, socket)

  @impl true
  def handle_event("keydown", %{"key" => "k", "ctrlKey" => true}, socket) do
    {:noreply, assign(socket, :show_new_task_drawer, !socket.assigns.show_new_task_drawer)}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("open_task_detail", params, socket),
    do: handle_open_task_detail(params, socket)

  @impl true
  def handle_event("update_task", params, socket),
    do: handle_update_task(params, socket, &load_tasks/1)

  @impl true
  def handle_event("delete_task", params, socket),
    do: handle_delete_task(params, socket, &load_tasks/1)

  @impl true
  def handle_event("start_agent_for_task", _params, socket) do
    {:noreply, put_flash(socket, :info, "Use the Kanban board to start agents for tasks")}
  end

  @impl true
  def handle_event("create_new_task", params, socket),
    do: handle_create_new_task(params, socket, &load_tasks/1)

  @impl true
  def handle_info(:tasks_changed, socket),
    do: handle_tasks_changed(socket, &load_tasks/1)

  defp load_tasks(socket) do
    project_id = socket.assigns.project_id

    TasksListHelpers.load_tasks(
      socket,
      fn query -> Tasks.search_tasks(query, project_id) end,
      fn opts -> Tasks.list_tasks_for_project(project_id, opts) end,
      fn opts -> Tasks.count_tasks_for_project(project_id, opts) end
    )
  end

  defp load_tasks_page(socket, page) do
    project_id = socket.assigns.project_id
    TasksListHelpers.load_tasks_page(socket, page, fn opts -> Tasks.list_tasks_for_project(project_id, opts) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6" phx-hook="GlobalKeydown" id="project-tasks-page">
      <div class="max-w-4xl mx-auto">
        <%!-- Search and New Task --%>
        <div class="mb-4 flex items-center gap-2 sm:gap-3">
          <form phx-change="search" class="flex-1 sm:max-w-sm">
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
              </div>
              <label for="project-tasks-search" class="sr-only">Search tasks</label>
              <input
                type="text"
                name="query"
                id="project-tasks-search"
                value={@search_query}
                placeholder="Search tasks..."
                class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-base"
                autocomplete="off"
              />
            </div>
          </form>

          <%!-- Mobile filter button --%>
          <button
            phx-click="open_filter_sheet"
            aria-label="Open filters"
            aria-haspopup="dialog"
            class="sm:hidden relative btn btn-ghost btn-sm btn-square h-11 w-11"
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

          <.link
            navigate={~p"/projects/#{@project.id}/kanban"}
            class="btn btn-sm sm:btn-xs btn-ghost border border-base-content/10 gap-1 min-h-0 h-11 sm:h-7"
            title="Kanban board"
          >
            <.icon name="hero-view-columns-mini" class="w-3.5 h-3.5" />
            <span class="hidden sm:inline">Kanban</span>
          </.link>
          <button
            phx-click="toggle_new_task_drawer"
            class="btn btn-sm btn-primary gap-1.5 min-h-0 h-11 sm:h-7 text-xs"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Task
          </button>
        </div>

        <%!-- Desktop Filters (hidden on mobile) --%>
        <div class="mb-4 hidden sm:flex items-center gap-2 flex-wrap">
          <%!-- Status filter pills --%>
          <button
            phx-click="filter_status"
            phx-value-state_id=""
            aria-pressed={is_nil(@filter_state_id)}
            class={[
              "btn btn-xs gap-1 h-11 sm:h-8 sm:min-h-0",
              if(is_nil(@filter_state_id), do: "btn-neutral", else: "btn-ghost text-base-content/50")
            ]}
          >
            All
          </button>
          <%= for state <- @workflow_states do %>
            <button
              phx-click="filter_status"
              phx-value-state_id={state.id}
              aria-pressed={@filter_state_id == state.id}
              class={[
                "btn btn-xs gap-1 h-11 sm:h-8 sm:min-h-0",
                if(@filter_state_id == state.id,
                  do: "btn-neutral",
                  else: "btn-ghost text-base-content/50"
                )
              ]}
            >
              {state.name}
            </button>
          <% end %>

          <div class="flex-1" />

          <%!-- Sort dropdown --%>
          <form phx-change="sort_by">
            <label for="project-tasks-sort" class="sr-only">Sort tasks</label>
            <select
              name="value"
              id="project-tasks-sort"
              class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 h-11 sm:h-8 sm:min-h-0 text-xs"
            >
              <option value="created_desc" selected={@sort_by == "created_desc"}>Newest first</option>
              <option value="created_asc" selected={@sort_by == "created_asc"}>Oldest first</option>
              <option value="priority" selected={@sort_by == "priority"}>Priority</option>
            </select>
          </form>
        </div>

        <%!-- Mobile filter bottom sheet --%>
        <FilterSheet.filter_sheet
          id="tasks-filter-sheet"
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
            id="project-tasks-list"
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
            id="project-tasks-sentinel"
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
            id="project-tasks-empty"
            icon="hero-clipboard-document-list"
            title={if @search_query != "", do: "No tasks found", else: "No tasks yet"}
            subtitle={
              if @search_query != "",
                do: "Try adjusting your search query",
                else: "Create a task to get started"
            }
          />
        <% end %>
      </div>
    </div>

    <!-- New Task Drawer -->
    <EyeInTheSkyWeb.Components.NewTaskDrawer.new_task_drawer
      id="new-task-drawer"
      show={@show_new_task_drawer}
      workflow_states={@workflow_states}
      toggle_event="toggle_new_task_drawer"
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
