defmodule EyeInTheSkyWeb.ProjectLive.Kanban do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Tasks, Notes}
  alias EyeInTheSkyWeb.Live.Shared.{KanbanFilters, TasksHelpers, BulkHelpers}
  alias EyeInTheSkyWeb.ProjectLive.Kanban.{BoardActions, FilterHandlers}

  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.Live.Shared.AgentHelpers, only: [handle_start_agent_for_task: 2]
  import EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers
  import EyeInTheSkyWeb.Components.KanbanFilterDrawer, only: [kanban_filter_drawer: 1]
  import EyeInTheSkyWeb.Components.KanbanToolbar, only: [kanban_toolbar: 1]
  import EyeInTheSkyWeb.Components.KanbanBulkBar, only: [kanban_bulk_bar: 1]
  import EyeInTheSkyWeb.Components.KanbanBoard, only: [kanban_board: 1]

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    id = params["id"]

    if connected?(socket) do
      EyeInTheSky.Events.subscribe_project_tasks(id)
      EyeInTheSky.Events.subscribe_agents()
      EyeInTheSky.Events.subscribe_agent_working()
    end

    socket =
      socket
      |> mount_project(params,
        sidebar_tab: :kanban,
        page_title_prefix: "Kanban",
        preload: [:agents]
      )
      |> init_assigns()

    if socket.assigns.project do
      {:ok, KanbanFilters.load_tasks(socket)}
    else
      {:ok, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events: search and drawers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:search_query, query) |> KanbanFilters.load_tasks()}
  end

  @impl true
  def handle_event("toggle_new_task_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_task_drawer, !socket.assigns.show_new_task_drawer)}
  end

  @impl true
  def handle_event("toggle_task_detail_drawer", _params, socket) do
    {:noreply, assign(socket, :show_task_detail_drawer, !socket.assigns.show_task_detail_drawer)}
  end

  # ---------------------------------------------------------------------------
  # Events: task CRUD (delegated to TasksHelpers)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_task_detail", params, socket),
    do: TasksHelpers.handle_open_task_detail(params, socket)

  @impl true
  def handle_event("update_task", params, socket),
    do: TasksHelpers.handle_update_task(params, socket, &KanbanFilters.load_tasks/1)

  @impl true
  def handle_event("delete_task", params, socket),
    do: TasksHelpers.handle_delete_task(params, socket, &KanbanFilters.load_tasks/1)

  @impl true
  def handle_event("create_new_task", params, socket),
    do: TasksHelpers.handle_create_new_task(params, socket, &KanbanFilters.load_tasks/1)

  @impl true
  def handle_event("quick_add_task", params, socket),
    do: TasksHelpers.handle_quick_add_task(params, socket, &KanbanFilters.load_tasks/1)

  @impl true
  def handle_event("archive_task", params, socket),
    do: TasksHelpers.handle_archive_task(params, socket, &KanbanFilters.load_tasks/1)

  @impl true
  def handle_event("add_task_annotation", params, socket),
    do: TasksHelpers.handle_add_task_annotation(params, socket)

  @impl true
  def handle_event("copy_task_to_project", params, socket),
    do: TasksHelpers.handle_copy_task_to_project(params, socket)

  # ---------------------------------------------------------------------------
  # Events: agent spawning
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("start_agent_for_task", params, socket),
    do: handle_start_agent_for_task(params, socket)

  # ---------------------------------------------------------------------------
  # Events: bulk operations (delegated to BulkHelpers)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_bulk_mode", _params, socket),
    do: BulkHelpers.handle_toggle_bulk_mode(socket)

  @impl true
  def handle_event("toggle_select_task", params, socket),
    do: BulkHelpers.handle_toggle_select_task(params, socket)

  @impl true
  def handle_event("select_all_column", params, socket),
    do: BulkHelpers.handle_select_all_column(params, socket)

  @impl true
  def handle_event("bulk_move", params, socket),
    do: BulkHelpers.handle_bulk_move(params, socket, &KanbanFilters.load_tasks/1)

  @impl true
  def handle_event("bulk_archive", _params, socket),
    do: BulkHelpers.handle_bulk_archive(socket, &KanbanFilters.load_tasks/1)

  @impl true
  def handle_event("bulk_delete", _params, socket),
    do: BulkHelpers.handle_bulk_delete(socket, &KanbanFilters.load_tasks/1)

  # ---------------------------------------------------------------------------
  # Events: filters (delegated to FilterHandlers)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("clear_filters", _params, socket),
    do: FilterHandlers.handle_clear_filters(socket)

  @impl true
  def handle_event("toggle_filter_drawer", _, socket),
    do: FilterHandlers.handle_toggle_filter_drawer(socket)

  @impl true
  def handle_event("update_filter", params, socket),
    do: FilterHandlers.handle_update_filter(params, socket)

  @impl true
  def handle_event("toggle_filters", _params, socket),
    do: FilterHandlers.handle_toggle_filters(socket)

  @impl true
  def handle_event("toggle_show_completed", _params, socket),
    do: FilterHandlers.handle_toggle_show_completed(socket)

  @impl true
  def handle_event("toggle_show_archived", _params, socket),
    do: FilterHandlers.handle_toggle_show_archived(socket)

  # ---------------------------------------------------------------------------
  # Events: board actions (delegated to BoardActions)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("cycle_tag_color", params, socket),
    do: BoardActions.handle_cycle_tag_color(params, socket)

  @impl true
  def handle_event("reorder_columns", params, socket),
    do: BoardActions.handle_reorder_columns(params, socket)

  @impl true
  def handle_event("reorder_tasks", params, socket),
    do: BoardActions.handle_reorder_tasks(params, socket)

  @impl true
  def handle_event("move_task", params, socket),
    do: BoardActions.handle_move_task(params, socket)

  @impl true
  def handle_event("show_quick_add", params, socket),
    do: BoardActions.handle_show_quick_add(params, socket)

  @impl true
  def handle_event("hide_quick_add", _params, socket),
    do: BoardActions.handle_hide_quick_add(socket)

  @impl true
  def handle_event("archive_column", params, socket),
    do: BoardActions.handle_archive_column(params, socket)

  # ---------------------------------------------------------------------------
  # PubSub handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:tasks_changed, socket) do
    socket = KanbanFilters.load_tasks(socket)

    socket =
      if socket.assigns.selected_task && socket.assigns.show_task_detail_drawer do
        task = Tasks.get_task!(socket.assigns.selected_task.id)
        notes = Notes.list_notes_for_task(task.id)
        socket |> assign(:selected_task, task) |> assign(:task_notes, notes)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_working, msg}, socket) do
    handle_agent_working(socket, msg, fn socket, session_id ->
      update(socket, :working_session_ids, &MapSet.put(&1, session_id))
    end)
  end

  @impl true
  def handle_info({:agent_stopped, msg}, socket) do
    handle_agent_stopped(socket, msg, fn socket, session_id ->
      update(socket, :working_session_ids, &MapSet.delete(&1, session_id))
    end)
  end

  @impl true
  def handle_info({:agent_updated, _}, socket), do: {:noreply, KanbanFilters.load_tasks(socket)}

  @impl true
  def handle_info({:agent_created, _}, socket), do: {:noreply, KanbanFilters.load_tasks(socket)}

  @impl true
  def handle_info({:agent_deleted, _}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:checklist_updated, task}, socket) do
    {:noreply, socket |> assign(:selected_task, task) |> KanbanFilters.load_tasks()}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="kanban-keyboard"
      phx-hook="KanbanKeyboard"
      class="px-4 sm:px-6 py-6 h-[calc(100dvh-7rem)] md:h-[calc(100dvh-4rem)] flex flex-col"
    >
      <% active_filter_count =
        if(@filter_priority, do: 1, else: 0) + MapSet.size(@filter_tags) +
          if(@filter_due_date, do: 1, else: 0) + if @filter_activity, do: 1, else: 0 %>
      <.kanban_toolbar
        search_query={@search_query}
        show_completed={@show_completed}
        bulk_mode={@bulk_mode}
        active_filter_count={active_filter_count}
      />

      <.kanban_bulk_bar
        bulk_mode={@bulk_mode}
        selected_tasks={@selected_tasks}
        workflow_states={@workflow_states}
      />

      <.kanban_board
        workflow_states={@workflow_states}
        tasks_by_state={@tasks_by_state}
        bulk_mode={@bulk_mode}
        selected_tasks={@selected_tasks}
        quick_add_column={@quick_add_column}
        working_session_ids={@working_session_ids}
      />
    </div>

    <EyeInTheSkyWeb.Components.NewTaskDrawer.new_task_drawer
      id="new-task-drawer"
      show={@show_new_task_drawer}
      workflow_states={@workflow_states}
      toggle_event="toggle_new_task_drawer"
      submit_event="create_new_task"
    />

    <EyeInTheSkyWeb.Components.TaskDetailDrawer.task_detail_drawer
      id="task-detail-drawer"
      show={@show_task_detail_drawer}
      task={@selected_task}
      notes={@task_notes}
      workflow_states={@workflow_states}
      projects={@all_projects}
      current_project_id={@project_id}
      focus={@task_detail_focus}
      toggle_event="toggle_task_detail_drawer"
      update_event="update_task"
      delete_event="delete_task"
      copy_event="copy_task_to_project"
    >
      <:checklist>
        <%= if @selected_task do %>
          <.live_component
            module={EyeInTheSkyWeb.Components.TaskChecklistComponent}
            id={"task-checklist-#{@selected_task.id}"}
            task={@selected_task}
          />
        <% end %>
      </:checklist>
    </EyeInTheSkyWeb.Components.TaskDetailDrawer.task_detail_drawer>

    <.kanban_filter_drawer
      show={@show_filter_drawer}
      search_query={@search_query}
      show_completed={@show_completed}
      show_archived={@show_archived}
      filter_due_date={@filter_due_date}
      filter_priority={@filter_priority}
      filter_tags={@filter_tags}
      filter_tag_mode={@filter_tag_mode}
      filter_activity={@filter_activity}
      available_tags={@available_tags}
    />
    """
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp init_assigns(socket) do
    socket
    |> assign(:search_query, "")
    |> assign(:filter_priority, nil)
    |> assign(:filter_tags, MapSet.new())
    |> assign(:filter_tag_mode, :and)
    |> assign(:workflow_states, Tasks.list_workflow_states())
    |> assign(:tasks, [])
    |> assign(:tasks_by_state, %{})
    |> assign(:available_tags, [])
    |> assign(:tag_counts, %{})
    |> assign(:show_new_task_drawer, false)
    |> assign(:show_task_detail_drawer, false)
    |> assign(:task_detail_focus, nil)
    |> assign(:selected_task, nil)
    |> assign(:task_notes, [])
    |> assign(:quick_add_column, nil)
    |> assign(:show_completed, false)
    |> assign(:show_archived, false)
    |> assign(:selected_tasks, MapSet.new())
    |> assign(:bulk_mode, false)
    |> assign(:all_projects, EyeInTheSky.Projects.list_projects())
    |> assign(:show_filters, false)
    |> assign(:show_filter_drawer, false)
    |> assign(:filter_due_date, nil)
    |> assign(:filter_activity, nil)
    |> assign(:working_session_ids, MapSet.new())
  end
end
