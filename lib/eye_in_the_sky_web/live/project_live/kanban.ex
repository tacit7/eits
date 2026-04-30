defmodule EyeInTheSkyWeb.ProjectLive.Kanban do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.{Notes, Projects, Tasks}
  alias EyeInTheSkyWeb.Live.Shared.{BulkHelpers, KanbanFilters, NotificationHelpers, TasksHelpers}
  alias EyeInTheSkyWeb.ProjectLive.Kanban.{BoardActions, DatePickerHandlers, FilterHandlers}

  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.Live.Shared.AgentHelpers, only: [handle_start_agent_for_task: 2]
  import EyeInTheSkyWeb.Live.Shared.AgentStatusHelpers
  import EyeInTheSkyWeb.Components.KanbanFilterDrawer, only: [kanban_filter_drawer: 1]
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
      |> FilterHandlers.assign_filter_count()

    if socket.assigns.project do
      {:ok, socket |> KanbanFilters.load_tasks() |> rebuild_session_status_ids()}
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
  def handle_event("toggle_overlay", %{"key" => key}, socket) do
    atom = String.to_existing_atom(key)
    {:noreply, assign(socket, atom, !socket.assigns[atom])}
  end

  @impl true
  def handle_event("toggle_new_task_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_task_drawer, !socket.assigns.show_new_task_drawer)}
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

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

  # ---------------------------------------------------------------------------
  # Events: date picker (delegated to DatePickerHandlers)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_date_picker", params, socket),
    do: DatePickerHandlers.handle_open_date_picker(params, socket)

  @impl true
  def handle_event("close_date_picker", _params, socket),
    do: DatePickerHandlers.handle_close_date_picker(socket)

  @impl true
  def handle_event("date_picker_prev_month", _params, socket),
    do: DatePickerHandlers.handle_date_picker_prev_month(socket)

  @impl true
  def handle_event("date_picker_next_month", _params, socket),
    do: DatePickerHandlers.handle_date_picker_next_month(socket)

  @impl true
  def handle_event("select_due_date", params, socket),
    do: DatePickerHandlers.handle_select_due_date(params, socket)

  @impl true
  def handle_event("save_due_date", params, socket),
    do: DatePickerHandlers.handle_save_due_date(params, socket)

  @impl true
  def handle_event("remove_due_date", params, socket),
    do: DatePickerHandlers.handle_remove_due_date(params, socket)

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

  @impl true
  def handle_event("clear_selection", _params, socket),
    do: {:noreply, assign(socket, :selected_tasks, MapSet.new())}

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
    socket =
      socket
      |> KanbanFilters.load_tasks()
      |> rebuild_session_status_ids()

    socket =
      if not is_nil(socket.assigns.selected_task) && socket.assigns.show_task_detail_drawer do
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
      socket
      |> update(:working_session_ids, &MapSet.put(&1, session_id))
      |> update(:waiting_session_ids, &MapSet.delete(&1, session_id))
    end)
  end

  @impl true
  def handle_info({:agent_stopped, %{status: "waiting", id: session_id}}, socket) do
    socket =
      socket
      |> update(:working_session_ids, &MapSet.delete(&1, session_id))
      |> update(:waiting_session_ids, &MapSet.put(&1, session_id))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_stopped, msg}, socket) do
    handle_agent_stopped(socket, msg, fn socket, session_id ->
      socket
      |> update(:working_session_ids, &MapSet.delete(&1, session_id))
      |> update(:waiting_session_ids, &MapSet.delete(&1, session_id))
    end)
  end

  @impl true
  def handle_info({:agent_updated, _}, socket), do: {:noreply, KanbanFilters.load_tasks(socket)}

  @impl true
  def handle_info({:agent_created, _}, socket), do: {:noreply, KanbanFilters.load_tasks(socket)}

  @impl true
  def handle_info({:agent_deleted, _}, socket), do: {:noreply, socket}

  def handle_info(_, socket), do: {:noreply, socket}

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
      data-bulk-mode={if @bulk_mode, do: "true", else: "false"}
      class="px-4 sm:px-6 py-6 h-[calc(100dvh-7rem)] md:h-[calc(100dvh-4rem)] flex flex-col"
    >
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
        waiting_session_ids={@waiting_session_ids}
      />
    </div>

    <EyeInTheSkyWeb.Components.NewTaskDrawer.new_task_drawer
      id="new-task-drawer"
      show={@show_new_task_drawer}
      workflow_states={@workflow_states}
      toggle_event={JS.push("toggle_overlay", value: %{key: "show_new_task_drawer"})}
      submit_event="create_new_task"
    />

    <EyeInTheSkyWeb.Components.TaskDetailDrawer.task_detail_drawer
      id="task-detail-drawer"
      show={@show_task_detail_drawer}
      task={@selected_task}
      notes={@task_notes}
      workflow_states={@workflow_states}
      projects={if @all_projects.ok?, do: @all_projects.result, else: []}
      current_project_id={@project_id}
      focus={@task_detail_focus}
      toggle_event={JS.push("toggle_overlay", value: %{key: "show_task_detail_drawer"})}
      close_event_name="toggle_overlay"
      close_event_key="show_task_detail_drawer"
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

    <EyeInTheSkyWeb.Components.DatePickerModal.date_picker_modal
      show={@show_date_picker}
      task={@date_picker_task}
      year={@date_picker_year}
      month={@date_picker_month}
      selected_date={@date_picker_selected}
    />
    """
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Seeds working_session_ids and waiting_session_ids from preloaded task sessions.
  # PubSub only delivers events that fire while the LiveView is connected, so without
  # this, any session that went working/waiting before mount is invisible to the board.
  defp rebuild_session_status_ids(socket) do
    {working_ids, waiting_ids} =
      (socket.assigns[:tasks] || [])
      |> Enum.flat_map(&(Map.get(&1, :sessions, []) || []))
      |> Enum.reduce({MapSet.new(), MapSet.new()}, fn session, {working, waiting} ->
        case session.status do
          "working" -> {MapSet.put(working, session.id), waiting}
          "waiting" -> {working, MapSet.put(waiting, session.id)}
          _ -> {working, waiting}
        end
      end)

    socket
    |> assign(:working_session_ids, working_ids)
    |> assign(:waiting_session_ids, waiting_ids)
  end

  defp init_assigns(socket) do
    socket
    |> assign(:top_bar_cta, %{label: "New Task", event: "toggle_new_task_drawer"})
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
    |> assign_async(:all_projects, fn -> {:ok, %{all_projects: Projects.list_projects()}} end)
    |> assign(:show_filters, false)
    |> assign(:show_filter_drawer, false)
    |> assign(:filter_due_date, nil)
    |> assign(:filter_activity, nil)
    |> assign(:working_session_ids, MapSet.new())
    |> assign(:waiting_session_ids, MapSet.new())
    |> assign(:show_date_picker, false)
    |> assign(:date_picker_task, nil)
    |> assign(:date_picker_year, nil)
    |> assign(:date_picker_month, nil)
    |> assign(:date_picker_selected, nil)
  end
end
