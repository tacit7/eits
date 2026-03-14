defmodule EyeInTheSkyWebWeb.ProjectLive.Kanban do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Tasks
  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWeb.Claude.AgentManager
  import EyeInTheSkyWebWeb.ControllerHelpers

  import EyeInTheSkyWebWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWebWeb.Components.TaskCard, only: [task_card: 1]

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    id = params["id"]

    if connected?(socket) do
      Phoenix.PubSub.subscribe(EyeInTheSkyWeb.PubSub, "tasks:#{id}")
    end

    socket =
      socket
      |> mount_project(params,
        sidebar_tab: :kanban,
        page_title_prefix: "Kanban",
        preload: [:agents]
      )
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
      |> assign(:selected_task, nil)
      |> assign(:task_notes, [])
      |> assign(:quick_add_column, nil)
      |> assign(:wip_limit, 8)
      |> assign(:show_completed, false)
      |> assign(:show_archived, false)
      |> assign(:selected_tasks, MapSet.new())
      |> assign(:bulk_mode, false)
      |> assign(:all_projects, Projects.list_projects())

    socket = if socket.assigns.project, do: load_tasks(socket), else: socket

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
  def handle_event("toggle_new_task_drawer", _params, socket) do
    {:noreply, assign(socket, :show_new_task_drawer, !socket.assigns.show_new_task_drawer)}
  end

  @impl true
  def handle_event("toggle_task_detail_drawer", _params, socket) do
    {:noreply, assign(socket, :show_task_detail_drawer, !socket.assigns.show_task_detail_drawer)}
  end

  @impl true
  def handle_event("open_task_detail", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)

    # Load notes for this task (handles both "task" and "tasks" parent_type)
    notes = Notes.list_notes_for_task(task.id)

    socket =
      socket
      |> assign(:selected_task, task)
      |> assign(:task_notes, notes)
      |> assign(:show_task_detail_drawer, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_task", params, socket) do
    task = socket.assigns.selected_task
    title = params["title"]
    description = params["description"]
    state_id = parse_int(params["state_id"], 0)
    priority = parse_int(params["priority"], 0)
    due_at = if params["due_at"] != "", do: params["due_at"], else: nil
    tags_string = params["tags"] || ""

    # Parse tags
    tag_names =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Update task
    case Tasks.update_task(task, %{
           title: title,
           description: description,
           state_id: state_id,
           priority: priority,
           due_at: due_at,
           updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
         }) do
      {:ok, updated_task} ->
        Tasks.replace_task_tags(task.id, tag_names)

        # Reload task with associations
        updated_task = Tasks.get_task!(updated_task.id)

        socket =
          socket
          |> assign(:selected_task, updated_task)
          |> load_tasks()
          |> put_flash(:info, "Task updated successfully")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update task")}
    end
  end

  @impl true
  def handle_event("delete_task", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)

    case Tasks.delete_task_with_associations(task) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:show_task_detail_drawer, false)
          |> assign(:selected_task, nil)
          |> load_tasks()
          |> put_flash(:info, "Task deleted successfully")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete task")}
    end
  end

  @impl true
  def handle_event("start_agent_for_task", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    project = socket.assigns.project

    task_prompt = "#{task.title}\n\n#{task.description || ""}" |> String.trim()

    opts = [
      description: task.title,
      instructions: task_prompt,
      project_id: project.id,
      project_path: project.path,
      model: "sonnet"
    ]

    case AgentManager.create_agent(opts) do
      {:ok, %{session: session}} ->
        Tasks.link_session_to_task(task.id, session.id)

        socket =
          socket
          |> assign(:show_task_detail_drawer, false)
          |> put_flash(:info, "Agent spawned for task: #{String.slice(task.title, 0..40)}")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to spawn agent: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("create_new_task", params, socket) do
    # Extract form data
    title = params["title"]
    description = params["description"]
    state_id = parse_int(params["state_id"], 0)
    priority = parse_int(params["priority"], 1)
    tags_string = params["tags"] || ""

    # Parse tags
    tag_names =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Generate UUID for task
    task_uuid = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    # Create task
    case Tasks.create_task(%{
           uuid: task_uuid,
           title: title,
           description: description,
           state_id: state_id,
           priority: priority,
           project_id: socket.assigns.project_id,
           created_at: now,
           updated_at: now
         }) do
      {:ok, task} ->
        Tasks.replace_task_tags(task.id, tag_names)

        socket =
          socket
          |> assign(:show_new_task_drawer, false)
          |> load_tasks()
          |> put_flash(:info, "Task created successfully")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to create task: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def handle_event("archive_task", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)

    case Tasks.archive_task(task) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:show_task_detail_drawer, false)
          |> assign(:selected_task, nil)
          |> load_tasks()
          |> put_flash(:info, "Task archived")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to archive task")}
    end
  end

  @impl true
  def handle_event("toggle_bulk_mode", _params, socket) do
    {:noreply,
     socket
     |> assign(:bulk_mode, !socket.assigns.bulk_mode)
     |> assign(:selected_tasks, MapSet.new())}
  end

  @impl true
  def handle_event("toggle_select_task", %{"task-uuid" => uuid}, socket) do
    selected = socket.assigns.selected_tasks

    updated =
      if MapSet.member?(selected, uuid),
        do: MapSet.delete(selected, uuid),
        else: MapSet.put(selected, uuid)

    {:noreply, assign(socket, :selected_tasks, updated)}
  end

  @impl true
  def handle_event("select_all_column", %{"state-id" => state_id_str}, socket) do
    state_id = parse_int(state_id_str, 0)
    column_uuids = Map.get(socket.assigns.tasks_by_state, state_id, []) |> Enum.map(& &1.uuid)
    current = socket.assigns.selected_tasks
    all_selected = Enum.all?(column_uuids, &MapSet.member?(current, &1))

    updated =
      if all_selected,
        do: Enum.reduce(column_uuids, current, &MapSet.delete(&2, &1)),
        else: Enum.reduce(column_uuids, current, &MapSet.put(&2, &1))

    {:noreply, assign(socket, :selected_tasks, updated)}
  end

  @impl true
  def handle_event("bulk_move", %{"state_id" => state_id_str}, socket) do
    state_id = parse_int(state_id_str, 0)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Enum.each(socket.assigns.selected_tasks, fn uuid ->
      task = Tasks.get_task_by_uuid!(uuid)
      Tasks.update_task(task, %{state_id: state_id, updated_at: now})
    end)

    {:noreply, socket |> assign(:selected_tasks, MapSet.new()) |> load_tasks()}
  end

  @impl true
  def handle_event("bulk_archive", _params, socket) do
    Enum.each(socket.assigns.selected_tasks, fn uuid ->
      task = Tasks.get_task_by_uuid!(uuid)
      Tasks.archive_task(task)
    end)

    {:noreply, socket |> assign(:selected_tasks, MapSet.new()) |> load_tasks() |> put_flash(:info, "Tasks archived")}
  end

  @impl true
  def handle_event("bulk_delete", _params, socket) do
    Enum.each(socket.assigns.selected_tasks, fn uuid ->
      task = Tasks.get_task_by_uuid!(uuid)
      Tasks.delete_task_with_associations(task)
    end)

    {:noreply, socket |> assign(:selected_tasks, MapSet.new()) |> load_tasks() |> put_flash(:info, "Tasks deleted")}
  end

  @impl true
  def handle_event("copy_task_to_project", %{"project_id" => project_id_str}, socket) do
    task = socket.assigns.selected_task
    target_project_id = parse_int(project_id_str, 0)

    if target_project_id > 0 and task do
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      tag_names = Enum.map(task.tags || [], & &1.name)

      case Tasks.create_task(%{
             uuid: Ecto.UUID.generate(),
             title: task.title,
             description: task.description,
             state_id: 1,
             priority: task.priority || 0,
             project_id: target_project_id,
             created_at: now,
             updated_at: now
           }) do
        {:ok, new_task} ->
          if tag_names != [], do: Tasks.replace_task_tags(new_task.id, tag_names)
          target = Projects.get_project!(target_project_id)

          socket =
            socket
            |> assign(:show_task_detail_drawer, false)
            |> put_flash(:info, "Task copied to #{target.name}")

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to copy task")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_task_annotation", %{"task_id" => task_id, "body" => body}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    body = String.trim(body)

    if body != "" do
      Notes.create_note(%{
        parent_type: "task",
        parent_id: task.uuid || to_string(task.id),
        body: body
      })

      notes = Notes.list_notes_for_task(task.id)
      {:noreply, assign(socket, :task_notes, notes)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filter_priority, nil) |> assign(:filter_tags, MapSet.new()) |> assign(:filter_tag_mode, :and) |> apply_filters()}
  end

  @impl true
  def handle_event("set_priority_filter", %{"priority" => priority}, socket) do
    new_priority = if priority == "", do: nil, else: String.to_integer(priority)
    current = socket.assigns.filter_priority
    priority_filter = if current == new_priority, do: nil, else: new_priority

    {:noreply, socket |> assign(:filter_priority, priority_filter) |> apply_filters()}
  end

  @impl true
  def handle_event("set_tag_filter", %{"tag" => tag}, socket) do
    current_tags = socket.assigns.filter_tags

    updated_tags =
      if MapSet.member?(current_tags, tag),
        do: MapSet.delete(current_tags, tag),
        else: MapSet.put(current_tags, tag)

    {:noreply, socket |> assign(:filter_tags, updated_tags) |> apply_filters()}
  end

  @impl true
  def handle_event("toggle_tag_filter_mode", _params, socket) do
    new_mode = if socket.assigns.filter_tag_mode == :and, do: :or, else: :and
    {:noreply, socket |> assign(:filter_tag_mode, new_mode) |> apply_filters()}
  end

  @impl true
  def handle_event("toggle_show_completed", _params, socket) do
    {:noreply, socket |> assign(:show_completed, !socket.assigns.show_completed) |> load_tasks()}
  end

  @impl true
  def handle_event("toggle_show_archived", _params, socket) do
    {:noreply, socket |> assign(:show_archived, !socket.assigns.show_archived) |> load_tasks()}
  end

  @tag_colors ~w(#6B7280 #EF4444 #F59E0B #10B981 #3B82F6 #8B5CF6 #EC4899 #06B6D4)

  @impl true
  def handle_event("cycle_tag_color", %{"tag-id" => tag_id_str}, socket) do
    tag_id = parse_int(tag_id_str, 0)
    tag = Tasks.get_tag!(tag_id)
    current_color = tag.color || List.first(@tag_colors)
    current_idx = Enum.find_index(@tag_colors, &(&1 == current_color)) || -1
    next_color = Enum.at(@tag_colors, rem(current_idx + 1, length(@tag_colors)))

    case Tasks.update_tag(tag, %{color: next_color}) do
      {:ok, _} -> {:noreply, load_tasks(socket)}
      {:error, _} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("reorder_columns", %{"column_ids" => column_ids}, socket) when is_list(column_ids) do
    ids = Enum.map(column_ids, &parse_int(&1, 0))
    Tasks.reorder_workflow_states(ids)
    {:noreply, assign(socket, :workflow_states, Tasks.list_workflow_states())}
  end

  @impl true
  def handle_event("reorder_tasks", %{"task_ids" => task_ids}, socket) when is_list(task_ids) do
    Tasks.reorder_tasks(task_ids)
    {:noreply, socket}
  end

  @impl true
  def handle_event("move_task", %{"task_id" => task_uuid, "state_id" => state_id_str}, socket) do
    state_id = parse_int(state_id_str, 0)
    task = Tasks.get_task_by_uuid!(task_uuid)

    case Tasks.update_task(task, %{
           state_id: state_id,
           updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
         }) do
      {:ok, _} ->
        {:noreply, load_tasks(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to move task")}
    end
  end

  @impl true
  def handle_event("show_quick_add", %{"state_id" => state_id}, socket) do
    {:noreply, assign(socket, :quick_add_column, parse_int(state_id, 0))}
  end

  @impl true
  def handle_event("hide_quick_add", _params, socket) do
    {:noreply, assign(socket, :quick_add_column, nil)}
  end

  @impl true
  def handle_event("quick_add_task", %{"title" => title, "state_id" => state_id_str}, socket) do
    title = String.trim(title)

    if title == "" do
      {:noreply, assign(socket, :quick_add_column, nil)}
    else
      state_id = parse_int(state_id_str, 0)
      task_uuid = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      case Tasks.create_task(%{
             uuid: task_uuid,
             title: title,
             state_id: state_id,
             priority: 0,
             project_id: socket.assigns.project_id,
             created_at: now,
             updated_at: now
           }) do
        {:ok, _task} ->
          socket =
            socket
            |> assign(:quick_add_column, nil)
            |> load_tasks()

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to create task")}
      end
    end
  end

  @impl true
  def handle_info(:tasks_changed, socket) do
    socket = load_tasks(socket)

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

  defp load_tasks(socket) do
    project_id = socket.assigns.project_id
    query = socket.assigns.search_query
    show_archived = socket.assigns.show_archived
    show_completed = socket.assigns.show_completed

    all_tasks =
      if query != "" and String.trim(query) != "" do
        Tasks.search_tasks(query, project_id)
      else
        Projects.get_project_tasks(project_id, include_archived: show_archived)
      end
      |> then(fn tasks ->
        if show_completed, do: tasks, else: Enum.reject(tasks, & &1.completed_at)
      end)
      |> Notes.with_notes_count()

    all_tag_refs = Enum.flat_map(all_tasks, fn t -> t.tags || [] end)

    available_tags =
      all_tag_refs
      |> Enum.uniq_by(& &1.name)
      |> Enum.sort_by(& &1.name)

    tag_counts =
      all_tag_refs
      |> Enum.frequencies_by(& &1.name)

    socket
    |> assign(:tasks, all_tasks)
    |> assign(:available_tags, available_tags)
    |> assign(:tag_counts, tag_counts)
    |> apply_filters()
  end

  defp apply_filters(socket) do
    tasks = socket.assigns.tasks
    priority_filter = socket.assigns.filter_priority
    filter_tags = socket.assigns.filter_tags

    tag_mode = socket.assigns.filter_tag_mode

    filtered =
      tasks
      |> filter_by_priority(priority_filter)
      |> filter_by_tags(filter_tags, tag_mode)

    tasks_by_state =
      Enum.group_by(filtered, fn task ->
        if task.state, do: task.state.id, else: nil
      end)

    assign(socket, :tasks_by_state, tasks_by_state)
  end

  defp filter_by_priority(tasks, nil), do: tasks
  defp filter_by_priority(tasks, priority), do: Enum.filter(tasks, &(&1.priority == priority))

  defp filter_by_tags(tasks, %MapSet{} = tags, mode) do
    if MapSet.size(tags) == 0 do
      tasks
    else
      Enum.filter(tasks, fn t ->
        task_tag_names = MapSet.new(t.tags || [], & &1.name)

        case mode do
          :and -> MapSet.subset?(tags, task_tag_names)
          :or -> MapSet.size(MapSet.intersection(tags, task_tag_names)) > 0
        end
      end)
    end
  end

  defp state_dot_color(color) when is_binary(color), do: color
  defp state_dot_color(_), do: "#6B7280"



  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 py-6 h-[calc(100dvh-7rem)] md:h-[calc(100dvh-4rem)] flex flex-col">
      <%!-- Search + New Task --%>
      <div class="mb-4 flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-3">
        <form phx-change="search" class="w-full sm:flex-1 sm:max-w-sm">
          <div class="relative">
            <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
              <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
            </div>
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search tasks..."
              phx-debounce="300"
              class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm"
              autocomplete="off"
            />
          </div>
        </form>

        <div class="flex items-center gap-1.5">
          <button
            phx-click="toggle_show_completed"
            class={"btn btn-xs gap-1 h-7 min-h-0 " <> if(@show_completed, do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
            title="Show completed tasks"
          >
            <.icon name="hero-check-circle-mini" class="w-3.5 h-3.5" />
            <span class="hidden sm:inline">Done</span>
          </button>
          <button
            phx-click="toggle_show_archived"
            class={"btn btn-xs gap-1 h-7 min-h-0 " <> if(@show_archived, do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
            title="Show archived tasks"
          >
            <.icon name="hero-archive-box-mini" class="w-3.5 h-3.5" />
            <span class="hidden sm:inline">Archived</span>
          </button>
          <button
            phx-click="toggle_bulk_mode"
            class={"btn btn-xs gap-1 h-7 min-h-0 " <> if(@bulk_mode, do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
            title="Bulk select mode"
          >
            <.icon name="hero-check-mini" class="w-3.5 h-3.5" />
            <span class="hidden sm:inline">Select</span>
          </button>
          <button
            phx-click="toggle_new_task_drawer"
            class="btn btn-sm btn-primary gap-1.5 h-9 sm:h-7 min-h-0 text-xs"
          >
            <.icon name="hero-plus-mini" class="w-3.5 h-3.5" /> New Task
          </button>
        </div>
      </div>

      <%!-- Filter chips --%>
      <%= if @available_tags != [] || @filter_priority || MapSet.size(@filter_tags) > 0 do %>
        <div class="mb-3 flex flex-wrap items-center gap-1.5">
          <%!-- Priority filters --%>
          <%= for {label, value, color} <- [{"High", 3, "text-error"}, {"Med", 2, "text-warning"}, {"Low", 1, "text-info"}] do %>
            <button
              phx-click="set_priority_filter"
              phx-value-priority={value}
              class={"btn btn-xs gap-1 " <> if(@filter_priority == value, do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
            >
              <span class={color}>●</span> {label}
            </button>
          <% end %>
          <%= if @available_tags != [] do %>
            <span class="text-base-content/15 text-xs">|</span>
            <%= for tag <- @available_tags do %>
              <div class="inline-flex items-center gap-0">
                <button
                  type="button"
                  phx-click="cycle_tag_color"
                  phx-value-tag-id={tag.id}
                  class="w-5 h-5 flex items-center justify-center rounded-l hover:bg-base-content/10 transition-colors"
                  title="Change tag color"
                >
                  <span class="w-2 h-2 rounded-full inline-block" style={"background-color: #{tag.color || "#6B7280"}"}></span>
                </button>
                <button
                  phx-click="set_tag_filter"
                  phx-value-tag={tag.name}
                  class={"btn btn-xs rounded-l-none gap-1 " <> if(MapSet.member?(@filter_tags, tag.name), do: "btn-neutral", else: "btn-ghost border border-base-content/10")}
                >
                  {tag.name}
                  <span class="text-[10px] opacity-50 tabular-nums">{Map.get(@tag_counts, tag.name, 0)}</span>
                </button>
              </div>
            <% end %>
          <% end %>
          <%= if MapSet.size(@filter_tags) >= 2 do %>
            <button
              phx-click="toggle_tag_filter_mode"
              class="btn btn-xs btn-ghost border border-base-content/10 text-base-content/50 font-mono"
              title={"Currently using #{@filter_tag_mode} logic. Click to switch."}
            >
              {if @filter_tag_mode == :and, do: "AND", else: "OR"}
            </button>
          <% end %>
          <%= if @filter_priority || MapSet.size(@filter_tags) > 0 do %>
            <button
              phx-click="clear_filters"
              class="btn btn-xs btn-ghost text-base-content/30 hover:text-base-content/60"
            >
              Clear
            </button>
          <% end %>
        </div>
      <% end %>

      <%!-- Bulk action bar --%>
      <%= if @bulk_mode and MapSet.size(@selected_tasks) > 0 do %>
        <div class="mb-2 flex items-center gap-2 px-2 py-1.5 rounded-lg bg-primary/10 border border-primary/20">
          <span class="text-xs font-medium text-primary">
            {MapSet.size(@selected_tasks)} selected
          </span>
          <span class="text-base-content/15">|</span>
          <span class="text-[11px] text-base-content/40">Move to:</span>
          <%= for state <- @workflow_states do %>
            <button
              phx-click="bulk_move"
              phx-value-state_id={state.id}
              class="btn btn-xs btn-ghost gap-1"
            >
              <span class="w-1.5 h-1.5 rounded-full" style={"background-color: #{state_dot_color(state.color)}"}></span>
              {state.name}
            </button>
          <% end %>
          <span class="text-base-content/15">|</span>
          <button
            phx-click="bulk_archive"
            class="btn btn-xs btn-ghost text-warning gap-1"
          >
            <.icon name="hero-archive-box-mini" class="w-3 h-3" /> Archive
          </button>
          <button
            phx-click="bulk_delete"
            data-confirm={"Delete #{MapSet.size(@selected_tasks)} tasks?"}
            class="btn btn-xs btn-ghost text-error gap-1"
          >
            <.icon name="hero-trash-mini" class="w-3 h-3" /> Delete
          </button>
        </div>
      <% end %>

      <%!-- Kanban columns --%>
      <div class="flex-1 min-h-0 overflow-x-auto">
        <div id="kanban-columns" phx-hook="SortableColumns" class="inline-flex gap-3 h-full min-w-full pb-2 snap-x snap-mandatory">
          <%= for state <- @workflow_states do %>
            <% column_tasks = Map.get(@tasks_by_state, state.id, []) %>
            <% task_count = length(column_tasks) %>
            <% wip_limit = @wip_limit %>
            <% over_wip = wip_limit > 0 and task_count > wip_limit %>
            <div class="flex-shrink-0 w-[84vw] max-w-80 md:w-72 flex flex-col h-full snap-start" data-column-id={state.id}>
              <%!-- Column header with colored accent --%>
              <div class="mb-2">
                <div
                  class="h-0.5 rounded-full mx-1 mb-2"
                  style={"background-color: #{state_dot_color(state.color)}"}
                />
                <div class="flex items-center gap-2 px-3 py-1" data-column-handle>
                  <%= if @bulk_mode do %>
                    <input
                      type="checkbox"
                      class="checkbox checkbox-xs checkbox-primary"
                      checked={column_tasks != [] and Enum.all?(column_tasks, &MapSet.member?(@selected_tasks, &1.uuid))}
                      phx-click="select_all_column"
                      phx-value-state-id={state.id}
                    />
                  <% end %>
                  <div class="flex items-center gap-1.5 cursor-grab active:cursor-grabbing">
                    <.icon name="hero-bars-2" class="w-3 h-3 text-base-content/20 hover:text-base-content/40" />
                    <div
                      class="w-2 h-2 rounded-full flex-shrink-0"
                      style={"background-color: #{state_dot_color(state.color)}"}
                    />
                  </div>
                  <span class="text-xs font-semibold text-base-content/70 uppercase tracking-wider">
                    {state.name}
                  </span>
                  <span class={[
                    "ml-auto inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 rounded-full text-[11px] font-medium tabular-nums",
                    if(over_wip, do: "bg-warning/20 text-warning", else: "bg-base-content/[0.06] text-base-content/40")
                  ]}>
                    {task_count}<%= if wip_limit > 0 do %>/{wip_limit}<% end %>
                  </span>
                </div>
              </div>

              <%!-- Column body --%>
              <div
                class="flex-1 min-h-0 overflow-y-auto rounded-xl bg-base-content/[0.04] p-2 space-y-1.5"
                id={"kanban-col-#{state.id}"}
                phx-hook="SortableKanban"
                data-state-id={state.id}
              >
                <%= if column_tasks == [] do %>
                  <div
                    data-empty-placeholder
                    class="flex flex-col items-center justify-center h-24 border border-dashed border-base-content/8 rounded-lg pointer-events-none"
                  >
                    <.icon name="hero-inbox" class="w-5 h-5 text-base-content/15 mb-1" />
                    <span class="text-[11px] text-base-content/20">No tasks</span>
                  </div>
                <% end %>
                <%= for task <- column_tasks do %>
                  <div class="flex items-start gap-1.5" data-task-id={task.uuid}>
                    <%= if @bulk_mode do %>
                      <input
                        type="checkbox"
                        class="checkbox checkbox-xs checkbox-primary mt-3 flex-shrink-0"
                        checked={MapSet.member?(@selected_tasks, task.uuid)}
                        phx-click="toggle_select_task"
                        phx-value-task-uuid={task.uuid}
                      />
                    <% end %>
                    <div class="flex-1 min-w-0">
                      <.task_card
                        variant="kanban"
                        task={task}
                        on_click="open_task_detail"
                        on_delete="delete_task"
                        id={"kanban-task-#{task.id}"}
                        phx-click="open_task_detail"
                        phx-value-task_id={task.uuid}
                      />
                    </div>
                  </div>
                <% end %>

                <%!-- Quick-add --%>
                <%= if @quick_add_column == state.id do %>
                  <form phx-submit="quick_add_task" class="mt-1">
                    <input type="hidden" name="state_id" value={state.id} />
                    <input
                      type="text"
                      name="title"
                      placeholder="Task title... (Esc to cancel)"
                      autofocus
                      phx-keydown="hide_quick_add"
                      phx-key="Escape"
                      class="input input-sm w-full bg-base-100 dark:bg-[hsl(60,2.1%,18.4%)] border-base-content/10 text-sm placeholder:text-base-content/25 focus:border-primary/30"
                    />
                  </form>
                <% else %>
                  <button
                    phx-click="show_quick_add"
                    phx-value-state_id={state.id}
                    class="mt-1 w-full flex items-center gap-1.5 px-2 py-1.5 rounded-lg text-[11px] text-base-content/25 hover:text-base-content/50 hover:bg-base-content/[0.04] transition-colors"
                  >
                    <.icon name="hero-plus-mini" class="w-3.5 h-3.5" />
                    <span>Add task</span>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <.live_component
      module={EyeInTheSkyWebWeb.Components.NewTaskDrawer}
      id="new-task-drawer"
      show={@show_new_task_drawer}
      workflow_states={@workflow_states}
      toggle_event="toggle_new_task_drawer"
      submit_event="create_new_task"
    />

    <.live_component
      module={EyeInTheSkyWebWeb.Components.TaskDetailDrawer}
      id="task-detail-drawer"
      show={@show_task_detail_drawer}
      task={@selected_task}
      notes={@task_notes}
      workflow_states={@workflow_states}
      projects={@all_projects}
      current_project_id={@project_id}
      toggle_event="toggle_task_detail_drawer"
      update_event="update_task"
      delete_event="delete_task"
      copy_event="copy_task_to_project"
    />
    """
  end
end
