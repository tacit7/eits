defmodule EyeInTheSkyWeb.ProjectLive.Notes do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Notes
  alias EyeInTheSkyWeb.Live.Shared.NotificationHelpers
  import EyeInTheSkyWeb.Components.NotesList
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
  import EyeInTheSkyWeb.ControllerHelpers, only: [parse_int: 1]
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [parse_id: 1]
  import EyeInTheSkyWeb.Live.Shared.NotesHelpers

  @impl true
  def mount(%{"id" => _} = params, _session, socket) do
    socket =
      socket
      |> mount_project(params,
        sidebar_tab: :notes,
        page_title_prefix: "Notes",
        preload: [:agents]
      )
      |> assign(:search_query, "")
      |> assign(:starred_filter, false)
      |> assign(:sort_by, "newest")
      |> assign(:notes, [])
      |> assign(:editing_note_id, nil)
      |> assign(:show_quick_note_modal, false)
      |> assign(:type_filter, "all")
      |> assign(:show_all, false)
      |> assign(:selected_note_ids, MapSet.new())
      |> assign(:notes_select_mode, false)
      |> assign_notes_new_href(params)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"show_all" => "true"} = _params, _uri, socket) do
    socket =
      socket
      |> assign(:show_all, true)
      |> then(fn s -> if connected?(s), do: load_notes(s), else: s end)

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    socket =
      socket
      |> assign(:show_all, false)
      |> then(fn s -> if connected?(s) && s.assigns.project, do: load_notes(s), else: s end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", params, socket),
    do: handle_search(params, socket, &load_notes/1)

  @impl true
  def handle_event("sort_notes", params, socket),
    do: handle_sort_notes(params, socket, &load_notes/1)

  @impl true
  def handle_event("filter_type", params, socket),
    do: handle_filter_type(params, socket, &load_notes/1)

  @impl true
  def handle_event("toggle_starred_filter", params, socket),
    do: handle_toggle_starred_filter(params, socket, &load_notes/1)

  @impl true
  def handle_event("toggle_star", params, socket),
    do: handle_toggle_star(params, socket, &load_notes/1)

  @impl true
  def handle_event("delete_note", params, socket),
    do: handle_delete_note(params, socket, &load_notes/1)

  @impl true
  def handle_event("archive_note", _params, socket) do
    {:noreply, put_flash(socket, :error, "Notes do not support archiving")}
  end

  @impl true
  def handle_event("toggle_select_note", %{"note_id" => note_id}, socket) do
    note_id = to_string(note_id)

    selected =
      if MapSet.member?(socket.assigns.selected_note_ids, note_id),
        do: MapSet.delete(socket.assigns.selected_note_ids, note_id),
        else: MapSet.put(socket.assigns.selected_note_ids, note_id)

    socket =
      socket
      |> assign(:selected_note_ids, selected)
      |> assign(:notes_select_mode, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_select_all_notes", _params, socket) do
    all_ids = MapSet.new(socket.assigns.notes, &to_string(&1.id))

    selected =
      if MapSet.equal?(socket.assigns.selected_note_ids, all_ids),
        do: MapSet.new(),
        else: all_ids

    {:noreply, assign(socket, :selected_note_ids, selected)}
  end

  @impl true
  def handle_event("delete_selected_notes", _params, socket) do
    int_ids =
      socket.assigns.selected_note_ids
      |> Enum.map(&parse_int/1)
      |> Enum.reject(&is_nil/1)

    {deleted, _} = Notes.delete_notes_by_ids(int_ids)

    socket =
      socket
      |> load_notes()
      |> clear_note_selection()
      |> put_flash(:info, "Deleted #{deleted} note#{if deleted != 1, do: "s"}")

    {:noreply, socket}
  end

  @impl true
  def handle_event("exit_select_mode_notes", _params, socket) do
    socket =
      socket
      |> assign(:notes_select_mode, false)
      |> assign(:selected_note_ids, MapSet.new())

    {:noreply, socket}
  end

  @impl true
  def handle_event("enter_select_mode_notes", _params, socket) do
    {:noreply, assign(socket, :notes_select_mode, true)}
  end

  @impl true
  def handle_event("set_notify_on_stop", params, socket),
    do: {:noreply, NotificationHelpers.set_notify_on_stop(socket, params)}

  @impl true
  def handle_event("edit_note", %{"note_id" => note_id}, socket) do
    case parse_id(note_id) do
      nil -> {:noreply, socket}
      id -> {:noreply, assign(socket, :editing_note_id, id)}
    end
  end

  @impl true
  def handle_event("note_saved", %{"note_id" => note_id, "body" => body}, socket) do
    with {:id, id} when not is_nil(id) <- {:id, parse_id(note_id)},
         note = Notes.get_note!(id),
         {:ok, _note} <- Notes.update_note(note, %{body: body}) do
      {:noreply,
       socket
       |> assign(:editing_note_id, nil)
       |> load_notes()}
    else
      {:id, nil} ->
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save note.")}
    end
  end

  @impl true
  def handle_event("note_edit_cancelled", _params, socket) do
    {:noreply, assign(socket, :editing_note_id, nil)}
  end

  @impl true
  def handle_event("open_quick_note_modal", _params, socket) do
    {:noreply, assign(socket, :show_quick_note_modal, true)}
  end

  @impl true
  def handle_event("close_quick_note_modal", _params, socket) do
    {:noreply, assign(socket, :show_quick_note_modal, false)}
  end

  @impl true
  def handle_event("create_quick_note", params, socket) do
    project = socket.assigns.project
    starred = params["starred"] == "1"

    case Notes.create_note(%{
           parent_type: "project",
           parent_id: to_string(project.id),
           title: params["title"] || "",
           body: params["body"] || "",
           starred: starred
         }) do
      {:ok, _note} ->
        {:noreply, socket |> assign(:show_quick_note_modal, false) |> load_notes()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create note")}
    end
  end

  defp load_notes(socket) do
    show_all = Map.get(socket.assigns, :show_all, false)
    project = socket.assigns.project
    query = String.trim(socket.assigns.search_query)

    notes =
      if show_all do
        fetch_notes(query,
          starred: socket.assigns.starred_filter,
          sort: socket.assigns.sort_by,
          type_filter: socket.assigns.type_filter
        )
      else
        agent_ids =
          if project && Map.has_key?(project, :agents),
            do: Enum.map(project.agents, & &1.id),
            else: []

        fetch_notes(query,
          project_id: project && project.id,
          agent_ids: agent_ids,
          starred: socket.assigns.starred_filter,
          sort: socket.assigns.sort_by,
          type_filter: socket.assigns.type_filter
        )
      end

    socket
    |> assign(:notes, notes)
  end

  defp clear_note_selection(socket) do
    socket
    |> assign(:selected_note_ids, MapSet.new())
    |> assign(:notes_select_mode, false)
  end

  defp fetch_notes("", opts), do: Notes.list_notes_filtered(opts)

  defp fetch_notes(query, opts) do
    agent_ids = Keyword.get(opts, :agent_ids, [])
    project_id = Keyword.get(opts, :project_id)
    starred = Keyword.get(opts, :starred)

    Notes.search_notes(
      query,
      agent_ids,
      Keyword.merge(opts, project_id: project_id, starred: starred)
    )
  end

  defp assign_notes_new_href(socket, %{"id" => id}) do
    case parse_id(id) do
      nil ->
        socket

      project_id ->
        href =
          "/notes/new?parent_type=project&parent_id=#{project_id}&return_to=/projects/#{project_id}/notes"

        assign(socket, :new_href, href)
    end
  end

  defp assign_notes_new_href(socket, _params), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Mobile-only controls bar (top bar is desktop-only) --%>
    <div class="md:hidden flex flex-wrap items-center gap-2 px-4 pt-3 pb-1">
      <button
        type="button"
        phx-click="open_quick_note_modal"
        class="flex items-center gap-1.5 px-3 py-1.5 min-h-[44px] rounded-lg text-xs font-medium bg-base-200/60 hover:bg-base-200 text-base-content/70 hover:text-base-content transition-colors"
      >
        <.icon name="hero-bolt" class="size-3.5" /> Quick Note
      </button>
      <.link
        navigate={@new_href || "/notes/new"}
        class="flex items-center gap-1.5 px-3 py-1.5 min-h-[44px] rounded-lg text-xs font-medium bg-primary text-primary-content hover:bg-primary/80 transition-colors"
      >
        <.icon name="hero-plus" class="size-3.5" /> New Note
      </.link>
      <button
        type="button"
        phx-click="toggle_starred_filter"
        aria-label={if @starred_filter, do: "Remove starred filter", else: "Filter by starred"}
        class={"flex items-center gap-1.5 px-3 py-1.5 min-h-[44px] rounded-lg text-xs font-medium transition-colors " <>
          if(@starred_filter,
            do: "bg-warning/10 text-warning",
            else: "text-base-content/35 hover:text-base-content/50 hover:bg-base-200/40"
          )}
      >
        <.icon
          name={if @starred_filter, do: "hero-star-solid", else: "hero-star"}
          class="size-3.5"
        />
      </button>
      <form phx-change="filter_type">
        <label for="notes-type-filter-mobile" class="sr-only">Filter by type</label>
        <select
          id="notes-type-filter-mobile"
          name="value"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-xs"
        >
          <option value="all" selected={@type_filter == "all"}>All Types</option>
          <option value="session" selected={@type_filter == "session"}>Session</option>
          <option value="agent" selected={@type_filter == "agent"}>Agent</option>
          <option value="project" selected={@type_filter == "project"}>Project</option>
          <option value="task" selected={@type_filter == "task"}>Task</option>
          <option value="system" selected={@type_filter == "system"}>System</option>
        </select>
      </form>
      <form phx-change="sort_notes">
        <label for="notes-sort-mobile" class="sr-only">Sort notes</label>
        <select
          id="notes-sort-mobile"
          name="value"
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-xs"
        >
          <option value="newest" selected={@sort_by == "newest"}>Newest</option>
          <option value="oldest" selected={@sort_by == "oldest"}>Oldest</option>
        </select>
      </form>
    </div>

    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="max-w-4xl mx-auto">
        <.notes_list
          notes={@notes}
          starred_filter={@starred_filter}
          search_query={@search_query}
          sort_by={@sort_by}
          type_filter={@type_filter}
          empty_id="project-notes-empty"
          editing_note_id={@editing_note_id}
          current_path={~p"/projects/#{@project.id}/notes"}
          selected_ids={@selected_note_ids}
          select_mode={@notes_select_mode}
        />
      </div>
    </div>

    <.quick_note_modal :if={@show_quick_note_modal} project={@project} />
    """
  end

  defp quick_note_modal(assigns) do
    ~H"""
    <div
      class="modal modal-open"
      phx-window-keydown="close_quick_note_modal"
      phx-key="Escape"
    >
      <div class="modal-box max-w-md p-0 overflow-hidden">
        <div class="flex items-center justify-between px-4 py-3 border-b border-base-content/10">
          <h2 class="text-sm font-semibold text-base-content">Quick Note</h2>
          <button
            type="button"
            phx-click="close_quick_note_modal"
            class="btn btn-ghost btn-xs btn-square min-h-[44px] min-w-[44px]"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
        <form phx-submit="create_quick_note" class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qn-title-proj">Title</label>
            <input
              type="text"
              name="title"
              id="qn-title-proj"
              required
              placeholder="Title..."
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 text-base min-h-[44px]"
              autocomplete="off"
              autofocus
            />
          </div>
          <div>
            <label class="sr-only" for="qn-body-proj">Body</label>
            <textarea
              name="body"
              id="qn-body-proj"
              rows="4"
              placeholder="Note content..."
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 resize-none text-base"
            ></textarea>
          </div>
          <label class="flex items-center gap-2 cursor-pointer select-none">
            <input type="checkbox" name="starred" value="1" class="checkbox checkbox-sm" />
            <.icon name="hero-star" class="size-3.5 text-warning/70" />
            <span class="text-sm text-base-content/70">Star this note</span>
          </label>
          <div class="flex justify-end gap-2 pt-1">
            <.form_actions
              submit_text="Create Note"
              cancel_event="close_quick_note_modal"
              size="sm"
            />
          </div>
        </form>
      </div>
      <div class="modal-backdrop bg-black/50" phx-click="close_quick_note_modal"></div>
    </div>
    """
  end
end
