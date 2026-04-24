defmodule EyeInTheSkyWeb.OverviewLive.Tasks do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Tasks

  alias EyeInTheSkyWeb.Components.FilterSheet
  alias EyeInTheSkyWeb.Components.TaskCard
  alias EyeInTheSkyWeb.ControllerHelpers
  alias EyeInTheSkyWeb.Live.Shared.TasksListHelpers
  import EyeInTheSkyWeb.Live.Shared.TasksHelpers

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EyeInTheSky.Events.subscribe_tasks()
    end

    workflow_states = if connected?(socket), do: Tasks.list_workflow_states(), else: []

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
      |> assign(:top_bar_cta, %{label: "New Task", event: "toggle_create_task_drawer"})
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
    state_id = if state_id == "", do: nil, else: ControllerHelpers.parse_int(state_id)

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

  defp load_tasks(socket) do
    TasksListHelpers.load_tasks(
      socket,
      &Tasks.search_tasks/1,
      &Tasks.list_tasks/1,
      &Tasks.count_tasks/1
    )
  end

  defp load_tasks_page(socket, page) do
    TasksListHelpers.load_tasks_page(socket, page, &Tasks.list_tasks/1)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="max-w-4xl mx-auto">
        <%!-- Mobile controls: filter + new task (desktop equivalents are in the top bar) --%>
        <div class="flex sm:hidden items-center gap-2 mb-4">
          <button
            phx-click="toggle_create_task_drawer"
            class="btn btn-sm btn-primary gap-1.5 h-11 text-xs"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Task
          </button>
          <button
            phx-click="open_filter_sheet"
            aria-label="Open filters"
            aria-haspopup="dialog"
            class="relative btn btn-ghost btn-sm btn-square min-h-[44px] min-w-[44px]"
          >
            <.icon name="hero-funnel-mini" class="w-4 h-4" />
            <%= if not is_nil(@filter_state_id) || @sort_by != "created_desc" do %>
              <span class="absolute top-0.5 right-0.5 w-2 h-2 bg-primary rounded-full" aria-hidden="true"></span>
            <% end %>
          </button>
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
              if @search_query != "" || not is_nil(@filter_state_id),
                do: "No tasks found",
                else: "No tasks yet"
            }
            subtitle={
              if @search_query != "" || not is_nil(@filter_state_id),
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
