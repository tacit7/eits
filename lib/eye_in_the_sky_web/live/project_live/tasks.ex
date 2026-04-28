defmodule EyeInTheSkyWeb.ProjectLive.Tasks do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Tasks
  alias EyeInTheSkyWeb.Components.FilterSheet
  alias EyeInTheSkyWeb.Components.TaskCard
  alias EyeInTheSkyWeb.ControllerHelpers
  alias EyeInTheSkyWeb.Live.Shared.BulkHelpers
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
      |> assign(:show_all, false)
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
      |> assign(:selected_task_ids, MapSet.new())
      |> assign(:tasks_select_mode, false)
      |> assign(:show_archive_confirm, false)
      |> assign(:loaded_task_ids, [])
      |> assign(:loaded_tasks, [])
      |> stream(:tasks, [], dom_id: fn t -> "pt-#{t.id}" end)

    socket =
      if connected?(socket) do
        assign(socket, :workflow_states, Tasks.list_workflow_states())
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"show_all" => "true"} = _params, _uri, socket) do
    socket =
      socket
      |> assign(:show_all, true)
      |> then(fn s -> if connected?(s), do: load_tasks(s), else: s end)

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> assign(:show_all, false)
      |> then(fn s -> if connected?(s), do: load_tasks(s), else: s end)

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
  def handle_event("sort_by", %{"by" => value}, socket) do
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
  def handle_event("toggle_select_task", %{"task_id" => task_id}, socket) do
    task_id = to_string(task_id)
    prev_select_mode = socket.assigns.tasks_select_mode

    selected =
      if MapSet.member?(socket.assigns.selected_task_ids, task_id),
        do: MapSet.delete(socket.assigns.selected_task_ids, task_id),
        else: MapSet.put(socket.assigns.selected_task_ids, task_id)

    new_select_mode = MapSet.size(selected) > 0
    select_mode_changed? = prev_select_mode != new_select_mode

    socket =
      socket
      |> assign(:selected_task_ids, selected)
      |> assign(:tasks_select_mode, new_select_mode)

    # Stream-insert changed rows so checkbox state and visibility re-render.
    # When select_mode changes (entering or exiting), re-insert ALL visible rows so their
    # checkbox visibility classes and phx-click handlers update.
    # Otherwise only re-insert the toggled row.
    socket =
      if select_mode_changed? do
        reinsert_all_tasks(socket)
      else
        case Enum.find(socket.assigns.loaded_tasks, fn t -> task_id(t) == task_id end) do
          nil -> socket
          task -> stream_insert(socket, :tasks, task)
        end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_select_all_tasks", _params, socket) do
    all_ids = MapSet.new(socket.assigns.loaded_task_ids)

    selected =
      if MapSet.equal?(socket.assigns.selected_task_ids, all_ids),
        do: MapSet.new(),
        else: all_ids

    socket =
      socket
      |> assign(:selected_task_ids, selected)
      |> assign(:tasks_select_mode, MapSet.size(selected) > 0)
      |> reinsert_all_tasks()

    {:noreply, socket}
  end

  @impl true
  def handle_event("enter_select_mode_tasks", _params, socket) do
    socket =
      socket
      |> assign(:tasks_select_mode, true)
      |> reinsert_all_tasks()

    {:noreply, socket}
  end

  @impl true
  def handle_event("bulk_set_state", %{"state_id" => state_id_str}, socket) do
    state_id = ControllerHelpers.parse_int(state_id_str)
    ids = socket.assigns.selected_task_ids

    cond do
      MapSet.size(ids) == 0 ->
        {:noreply, socket}

      is_nil(state_id) ->
        {:noreply, put_flash(socket, :error, "Invalid state")}

      true ->
        results =
          Enum.map(ids, fn task_id ->
            case Tasks.get_task_by_uuid_or_id(task_id) do
              {:ok, task} -> match?({:ok, _}, Tasks.update_task_state(task, state_id))
              {:error, :not_found} -> false
            end
          end)

        moved = Enum.count(results, & &1)

        {flash_level, flash_msg} = BulkHelpers.build_bulk_flash(moved, length(results), "task")

        socket =
          socket
          |> assign(:selected_task_ids, MapSet.new())
          |> assign(:tasks_select_mode, false)
          |> load_tasks()
          |> put_flash(flash_level, flash_msg)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("confirm_archive_selected_tasks", _params, socket) do
    {:noreply, assign(socket, :show_archive_confirm, true)}
  end

  @impl true
  def handle_event("cancel_archive_selected_tasks", _params, socket) do
    {:noreply, assign(socket, :show_archive_confirm, false)}
  end

  @impl true
  def handle_event("archive_selected_tasks", _params, socket) do
    if MapSet.size(socket.assigns.selected_task_ids) == 0 do
      {:noreply, assign(socket, :show_archive_confirm, false)}
    else
      results =
        Enum.map(socket.assigns.selected_task_ids, fn task_id ->
          case Tasks.get_task_by_uuid_or_id(task_id) do
            {:ok, task} -> match?({:ok, _}, Tasks.archive_task(task))
            {:error, :not_found} -> false
          end
        end)

      archived = Enum.count(results, & &1)

      {flash_level, flash_msg} = BulkHelpers.build_bulk_flash(archived, length(results), "task")

      socket =
        socket
        |> assign(:show_archive_confirm, false)
        |> assign(:selected_task_ids, MapSet.new())
        |> assign(:tasks_select_mode, false)
        |> load_tasks()
        |> put_flash(flash_level, flash_msg)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_selected_tasks", _params, socket) do
    ids = socket.assigns.selected_task_ids

    deleted =
      Enum.count(ids, fn task_id ->
        case Tasks.get_task_by_uuid_or_id(task_id) do
          {:ok, task} -> match?({:ok, _}, Tasks.delete_task_with_associations(task))
          {:error, :not_found} -> false
        end
      end)

    socket =
      socket
      |> assign(:selected_task_ids, MapSet.new())
      |> assign(:tasks_select_mode, false)
      |> load_tasks()
      |> put_flash(:info, "Deleted #{deleted} task#{if deleted != 1, do: "s"}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("exit_select_mode_tasks", _params, socket) do
    socket =
      socket
      |> assign(:tasks_select_mode, false)
      |> assign(:selected_task_ids, MapSet.new())
      |> reinsert_all_tasks()

    {:noreply, socket}
  end

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

  def handle_info(_, socket), do: {:noreply, socket}

  defp load_tasks(socket) do
    show_all = Map.get(socket.assigns, :show_all, false)
    project_id = socket.assigns.project_id

    if show_all do
      TasksListHelpers.load_tasks(
        socket,
        fn query -> Tasks.search_tasks(query) end,
        fn opts -> Tasks.list_tasks(opts) end,
        fn opts -> Tasks.count_tasks(opts) end
      )
    else
      TasksListHelpers.load_tasks(
        socket,
        fn query -> Tasks.search_tasks(query, project_id) end,
        fn opts -> Tasks.list_tasks_for_project(project_id, opts) end,
        fn opts -> Tasks.count_tasks_for_project(project_id, opts) end
      )
    end
  end

  defp reinsert_all_tasks(socket) do
    Enum.reduce(socket.assigns.loaded_tasks, socket, fn task, acc ->
      stream_insert(acc, :tasks, task)
    end)
  end

  defp task_id(task), do: task.uuid || to_string(task.id)

  defp load_tasks_page(socket, page) do
    show_all = Map.get(socket.assigns, :show_all, false)
    project_id = socket.assigns.project_id

    if show_all do
      TasksListHelpers.load_tasks_page(socket, page, fn opts ->
        Tasks.list_tasks(opts)
      end)
    else
      TasksListHelpers.load_tasks_page(socket, page, fn opts ->
        Tasks.list_tasks_for_project(project_id, opts)
      end)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6" phx-hook="GlobalKeydown" id="project-tasks-page">
      <div class="max-w-4xl mx-auto">
        <%!-- Mobile-only action bar --%>
        <div class="mb-4 flex md:hidden items-center justify-end gap-2">
          <button
            :if={!@tasks_select_mode && @task_count > 0}
            phx-click="enter_select_mode_tasks"
            class="btn btn-ghost btn-sm gap-1 h-11 text-xs text-base-content/50"
          >
            <.icon name="hero-check-circle-mini" class="size-3.5" /> Select
          </button>
          <button
            phx-click="open_filter_sheet"
            aria-label="Open filters"
            aria-haspopup="dialog"
            class="relative btn btn-ghost btn-sm btn-square h-11 w-11"
          >
            <.icon name="hero-funnel-mini" class="size-4" />
            <%= if not is_nil(@filter_state_id) || @sort_by != "created_desc" do %>
              <span class="absolute top-0.5 right-0.5 w-2 h-2 bg-primary rounded-full" aria-hidden="true">
              </span>
            <% end %>
          </button>
          <button
            phx-click="toggle_new_task_drawer"
            class="btn btn-sm btn-primary gap-1.5 min-h-0 h-11 text-xs"
          >
            <.icon name="hero-plus-mini" class="size-3.5" /> New Task
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

        <%= if @task_count > 0 do %>
          <%!-- Bulk-select toolbar --%>
          <%= if @tasks_select_mode do %>
            <div class="mb-3 flex items-center gap-3 px-2 py-1.5">
              <div phx-click="toggle_select_all_tasks" class="cursor-pointer">
                <.square_checkbox
                  checked={MapSet.size(@selected_task_ids) == @task_count}
                  indeterminate={MapSet.size(@selected_task_ids) > 0 && MapSet.size(@selected_task_ids) < @task_count}
                  aria-label="Select all tasks"
                />
              </div>
              <%= if MapSet.size(@selected_task_ids) > 0 do %>
                <span class="text-mini text-base-content/50 font-medium">
                  {MapSet.size(@selected_task_ids)} selected
                </span>
                <details
                  id="tasks-bulk-state-dropdown"
                  phx-update="ignore"
                  class="dropdown"
                >
                  <summary class="btn btn-ghost btn-xs gap-1 min-h-[44px] text-base-content/70 hover:text-base-content [list-style:none] [&::-webkit-details-marker]:hidden">
                    <.icon name="hero-arrows-right-left-mini" class="size-3.5" /> Move to <.icon name="hero-chevron-down-mini" class="size-3 opacity-50" />
                  </summary>
                  <ul class="dropdown-content z-50 mt-1 bg-base-100 border border-base-content/10 rounded-lg shadow-lg p-1 min-w-[140px]">
                    <%= for state <- @workflow_states do %>
                      <li>
                        <button
                          phx-click="bulk_set_state"
                          phx-value-state_id={state.id}
                          onclick="this.closest('details').removeAttribute('open')"
                          class="flex items-center gap-2 w-full px-3 py-1.5 text-left text-mini rounded hover:bg-base-content/5 text-base-content/70 hover:text-base-content"
                        >
                          <span
                            class="inline-block w-2 h-2 rounded-full flex-shrink-0"
                            style={"background-color: #{state.color}"}
                            aria-hidden="true"
                          />
                          {state.name}
                        </button>
                      </li>
                    <% end %>
                  </ul>
                </details>
                <button
                  phx-click="confirm_archive_selected_tasks"
                  class="btn btn-ghost btn-xs text-warning/70 hover:text-warning hover:bg-warning/10 gap-1 min-h-[44px] min-w-[44px]"
                >
                  <.icon name="hero-archive-box-mini" class="size-3.5" /> Archive
                </button>
                <button
                  phx-click="delete_selected_tasks"
                  data-confirm={"Delete #{MapSet.size(@selected_task_ids)} task#{if MapSet.size(@selected_task_ids) != 1, do: "s"}?"}
                  class="btn btn-ghost btn-xs text-error/70 hover:text-error hover:bg-error/10 gap-1 min-h-[44px] min-w-[44px]"
                >
                  <.icon name="hero-trash-mini" class="size-3.5" /> Delete
                </button>
              <% else %>
                <span class="text-mini text-base-content/30">{@task_count} tasks</span>
              <% end %>
              <button
                phx-click="exit_select_mode_tasks"
                class="ml-auto btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px] text-base-content/40 hover:text-base-content/70"
                aria-label="Exit select mode"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
          <% end %>

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
                select_mode={@tasks_select_mode}
                selected={MapSet.member?(@selected_task_ids, task.uuid || to_string(task.id))}
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

    <!-- Bulk archive confirm modal -->
    <dialog
      id="tasks-archive-confirm-modal"
      class={"modal modal-bottom sm:modal-middle " <> if(@show_archive_confirm, do: "modal-open", else: "")}
    >
      <div class="modal-box w-full sm:max-w-sm pb-[env(safe-area-inset-bottom)]">
        <h3 class="text-lg font-bold">Archive tasks</h3>
        <p class="py-4 text-sm text-base-content/70">
          <% count = MapSet.size(@selected_task_ids) %>
          Archive {count} selected task{if count == 1, do: "", else: "s"}?
          Archived tasks can be unarchived later.
        </p>
        <div class="modal-action">
          <button phx-click="cancel_archive_selected_tasks" class="btn btn-sm btn-ghost min-h-[44px]">
            Cancel
          </button>
          <button phx-click="archive_selected_tasks" class="btn btn-sm btn-warning min-h-[44px]">
            Archive
          </button>
        </div>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button phx-click="cancel_archive_selected_tasks">close</button>
      </form>
    </dialog>
    """
  end
end
