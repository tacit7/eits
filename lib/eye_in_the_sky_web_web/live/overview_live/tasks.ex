defmodule EyeInTheSkyWebWeb.OverviewLive.Tasks do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Tasks
  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWebWeb.Components.TaskCard

  @per_page 50

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
  def handle_event("open_filter_sheet", _params, socket) do
    {:noreply, assign(socket, :show_filter_sheet, true)}
  end

  @impl true
  def handle_event("close_filter_sheet", _params, socket) do
    {:noreply, assign(socket, :show_filter_sheet, false)}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    if socket.assigns.has_more do
      next_page = socket.assigns.page + 1
      {:noreply, load_tasks_page(socket, next_page)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_task_detail", %{"task_id" => task_id}, socket) do
    task = Tasks.get_task_by_uuid_or_id!(task_id)
    notes = Notes.list_notes_for_task(task.id)

    socket =
      socket
      |> assign(:selected_task, task)
      |> assign(:task_notes, notes)
      |> assign(:show_task_detail_drawer, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_task_detail_drawer", _params, socket) do
    {:noreply, assign(socket, :show_task_detail_drawer, !socket.assigns.show_task_detail_drawer)}
  end

  @impl true
  def handle_event("update_task", params, socket) do
    task = socket.assigns.selected_task
    title = params["title"]
    description = params["description"]
    state_id = parse_int(params["state_id"])
    priority = parse_int(params["priority"], 0)
    due_at = if params["due_at"] != "", do: params["due_at"], else: nil
    tags_string = params["tags"] || ""

    tag_names =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

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

        updated_task = Tasks.get_task!(updated_task.id)

        socket =
          socket
          |> assign(:selected_task, updated_task)
          |> load_tasks()
          |> put_flash(:info, "Task updated")

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
          |> put_flash(:info, "Task deleted")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete task")}
    end
  end

  @impl true
  def handle_event("start_agent_for_task", _params, socket) do
    {:noreply, put_flash(socket, :info, "Open the project Kanban board to start agents")}
  end

  @impl true
  def handle_info(:tasks_changed, socket) do
    {:noreply, load_tasks(socket)}
  end

  defp parse_int(s, default \\ 0) do
    case Integer.parse(s || "") do
      {n, ""} -> n
      _ -> default
    end
  end

  defp state_id_from_filter("all"), do: nil

  defp state_id_from_filter(state_id_str) do
    case Integer.parse(state_id_str) do
      {id, ""} -> id
      _ -> nil
    end
  end

  # Resets to page 1, replaces the task list
  defp load_tasks(socket) do
    query = socket.assigns.search_query
    state_filter = socket.assigns.state_filter
    state_id = state_id_from_filter(state_filter)

    if query != "" and String.trim(query) != "" do
      # Search: return all results (no pagination), filter by state in memory
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
      tasks = Tasks.list_tasks(limit: @per_page, offset: 0, state_id: state_id)

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
    state_id = state_id_from_filter(socket.assigns.state_filter)
    offset = (page - 1) * @per_page
    total = socket.assigns.total_tasks

    new_tasks = Tasks.list_tasks(limit: @per_page, offset: offset, state_id: state_id)

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

          <%!-- Mobile filter button --%>
          <button
            phx-click="open_filter_sheet"
            aria-label="Open filters"
            aria-haspopup="dialog"
            class="sm:hidden relative btn btn-ghost btn-sm btn-square"
          >
            <.icon name="hero-funnel-mini" class="w-4 h-4" />
            <%= if @state_filter != "all" do %>
              <span class="absolute top-0.5 right-0.5 w-2 h-2 bg-primary rounded-full" aria-hidden="true"></span>
            <% end %>
          </button>

          <%!-- Desktop filter pills --%>
          <div class="hidden sm:flex items-center gap-1 bg-base-200/40 rounded-lg p-0.5">
            <button
              phx-click="filter_state"
              phx-value-state="all"
              aria-pressed={@state_filter == "all"}
              class={"px-3 py-1.5 rounded-md text-xs font-medium transition-all duration-150 " <>
                if(@state_filter == "all",
                  do: "bg-base-100 text-base-content shadow-sm",
                  else: "text-base-content/60 hover:text-base-content/85"
                )}
            >
              All
            </button>
            <%= for state <- @workflow_states do %>
              <button
                phx-click="filter_state"
                phx-value-state={to_string(state.id)}
                aria-pressed={@state_filter == to_string(state.id)}
                class={"px-3 py-1.5 rounded-md text-xs font-medium transition-all duration-150 " <>
                  if(@state_filter == to_string(state.id),
                    do: "bg-base-100 text-base-content shadow-sm",
                    else: "text-base-content/60 hover:text-base-content/85"
                  )}
              >
                {state.name}
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Mobile filter bottom sheet --%>
        <%= if @show_filter_sheet do %>
          <div
            class="fixed inset-0 z-40 bg-black/40"
            phx-click="close_filter_sheet"
            aria-hidden="true"
          >
          </div>
          <div
            class="fixed inset-x-0 bottom-0 z-50 rounded-t-2xl bg-base-100 shadow-xl safe-bottom-sheet"
            role="dialog"
            aria-modal="true"
            aria-label="Filter tasks"
            id="overview-tasks-filter-sheet"
            phx-window-keydown="close_filter_sheet"
            phx-key="Escape"
          >
            <div class="flex justify-center pt-3 pb-1">
              <div class="w-10 h-1 rounded-full bg-base-content/20"></div>
            </div>
            <div class="px-5 pb-6 pt-2">
              <div class="flex items-center justify-between mb-4">
                <h2 class="text-sm font-semibold">Filter by Status</h2>
                <button
                  phx-click="close_filter_sheet"
                  class="btn btn-ghost btn-xs btn-square"
                  aria-label="Close filter panel"
                >
                  <.icon name="hero-x-mark-mini" class="w-4 h-4" />
                </button>
              </div>

              <fieldset class="mb-6">
                <legend class="sr-only">Status filter</legend>
                <div class="flex flex-wrap gap-2">
                  <button
                    phx-click="filter_state"
                    phx-value-state="all"
                    aria-pressed={@state_filter == "all"}
                    class={"btn btn-sm " <>
                      if(@state_filter == "all",
                        do: "btn-primary",
                        else: "btn-ghost border border-base-content/15"
                      )}
                  >
                    All
                  </button>
                  <%= for state <- @workflow_states do %>
                    <button
                      phx-click="filter_state"
                      phx-value-state={to_string(state.id)}
                      aria-pressed={@state_filter == to_string(state.id)}
                      class={"btn btn-sm " <>
                        if(@state_filter == to_string(state.id),
                          do: "btn-primary",
                          else: "btn-ghost border border-base-content/15"
                        )}
                    >
                      {state.name}
                    </button>
                  <% end %>
                </div>
              </fieldset>

              <div class="flex gap-3">
                <button phx-click="close_filter_sheet" class="btn btn-primary flex-1">
                  Apply
                </button>
                <button
                  phx-click="filter_state"
                  phx-value-state="all"
                  class="btn btn-ghost"
                  aria-label="Reset filters"
                >
                  Reset
                </button>
              </div>
            </div>
          </div>
        <% end %>

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
            class="divide-y divide-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm px-5"
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
              if @search_query != "" || @state_filter != "all",
                do: "No tasks found",
                else: "No tasks yet"
            }
            subtitle={
              if @search_query != "" || @state_filter != "all",
                do: "Try adjusting your search or filters",
                else: "Tasks created by agents will appear here"
            }
          />
        <% end %>
      </div>
    </div>

    <!-- Task Detail Drawer -->
    <.live_component
      module={EyeInTheSkyWebWeb.Components.TaskDetailDrawer}
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
