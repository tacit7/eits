defmodule EyeInTheSkyWeb.ProjectLive.Tasks do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Tasks
  alias EyeInTheSkyWeb.Components.FilterSheet
  alias EyeInTheSkyWeb.Components.TaskCard
  alias EyeInTheSkyWeb.ControllerHelpers
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  alias EyeInTheSkyWeb.Live.Shared.TasksListHelpers
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.Helpers.PubSubHelpers
  import EyeInTheSkyWeb.Live.Shared.TasksHelpers

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    if connected?(socket), do: subscribe_tasks()

    socket =
      socket
      |> mount_project(params,
        sidebar_tab: :tasks,
        page_title_prefix: "Tasks",
        preload: [:agents]
      )
      |> assign(:top_bar_cta, %{label: "New Task", event: "toggle_new_task_drawer"})
      |> assign(:search_query, "")
      |> assign(:filter_state_id, nil)
      |> assign(:sort_by, "created_desc")
      |> assign(:workflow_states, [])
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

    socket =
      if connected?(socket) do
        socket
        |> assign(:workflow_states, Tasks.list_workflow_states())
        |> then(fn s -> if s.assigns.project, do: load_tasks(s), else: s end)
      else
        socket
      end

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
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

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

    TasksListHelpers.load_tasks_page(socket, page, fn opts ->
      Tasks.list_tasks_for_project(project_id, opts)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6" phx-hook="GlobalKeydown" id="project-tasks-page">
      <div class="max-w-4xl mx-auto">
        <%!-- Mobile-only action bar --%>
        <div class="mb-4 flex md:hidden items-center justify-end gap-2">
          <button
            phx-click="open_filter_sheet"
            aria-label="Open filters"
            aria-haspopup="dialog"
            class="relative btn btn-ghost btn-sm btn-square h-11 w-11"
          >
            <.icon name="hero-funnel-mini" class="w-4 h-4" />
            <%= if not is_nil(@filter_state_id) || @sort_by != "created_desc" do %>
              <span class="absolute top-0.5 right-0.5 w-2 h-2 bg-primary rounded-full" aria-hidden="true">
              </span>
            <% end %>
          </button>
          <button
            phx-click="toggle_new_task_drawer"
            class="btn btn-sm btn-primary gap-1.5 min-h-0 h-11 text-xs"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Task
          </button>
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
