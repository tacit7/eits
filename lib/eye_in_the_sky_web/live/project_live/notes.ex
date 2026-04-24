defmodule EyeInTheSkyWeb.ProjectLive.Notes do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Notes
  import EyeInTheSkyWeb.Components.NotesList
  import EyeInTheSkyWeb.Helpers.ProjectLiveHelpers
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
      |> assign(:notes_sort_by, "newest")
      |> assign(:notes, [])
      |> assign(:editing_note_id, nil)
      |> assign(:show_quick_note_modal, false)
      |> assign(:type_filter, "all")
      |> assign(:show_all, false)
      |> assign(:selected_note_ids, MapSet.new())
      |> assign(:notes_select_mode, false)

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
    ids = socket.assigns.selected_note_ids

    deleted =
      Enum.count(ids, fn id ->
        case Integer.parse(id) do
          {int_id, ""} ->
            note = Notes.get_note!(int_id)
            match?({:ok, _}, Notes.delete_note(note))

          _ ->
            false
        end
      end)

    socket =
      socket
      |> assign(:selected_note_ids, MapSet.new())
      |> assign(:notes_select_mode, false)
      |> load_notes()
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
  def handle_event("edit_note", %{"note_id" => note_id}, socket) do
    case parse_id(note_id) do
      nil -> {:noreply, socket}
      id -> {:noreply, assign(socket, :editing_note_id, id)}
    end
  end

  @impl true
  def handle_event("note_saved", %{"note_id" => note_id, "body" => body}, socket) do
    case parse_id(note_id) do
      nil ->
        {:noreply, socket}

      id ->
        note = Notes.get_note!(id)

        case Notes.update_note(note, %{body: body}) do
          {:ok, _note} ->
            socket =
              socket
              |> assign(:editing_note_id, nil)
              |> load_notes()

            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to save note.")}
        end
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
    query = socket.assigns.search_query

    notes =
      if show_all do
        if String.trim(query) != "" do
          Notes.search_notes(query, [], starred: socket.assigns.starred_filter)
        else
          Notes.list_notes_filtered(
            starred: socket.assigns.starred_filter,
            sort: socket.assigns.notes_sort_by,
            type_filter: socket.assigns.type_filter
          )
        end
      else
        agent_ids =
          if project && Map.has_key?(project, :agents),
            do: Enum.map(project.agents, & &1.id),
            else: []

        if String.trim(query) != "" do
          Notes.search_notes(query, agent_ids,
            project_id: project && project.id,
            starred: socket.assigns.starred_filter
          )
        else
          Notes.list_notes_filtered(
            project_id: project && project.id,
            agent_ids: agent_ids,
            starred: socket.assigns.starred_filter,
            sort: socket.assigns.notes_sort_by,
            type_filter: socket.assigns.type_filter
          )
        end
      end

    socket
    |> assign(:notes, notes)
    |> assign(:selected_note_ids, MapSet.new())
    |> assign(:notes_select_mode, false)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="max-w-4xl mx-auto">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between mb-6">
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="open_quick_note_modal"
              class="flex items-center gap-1.5 px-3 py-1.5 min-h-[44px] rounded-lg text-xs font-medium bg-base-200/60 hover:bg-base-200 text-base-content/70 hover:text-base-content transition-colors"
            >
              <.icon name="hero-bolt" class="w-3.5 h-3.5" /> Quick Note
            </button>
            <.link
              navigate={
                ~p"/notes/new?#{%{parent_type: "project", parent_id: @project.id, return_to: "/projects/#{@project.id}/notes"}}"
              }
              class="flex items-center gap-1.5 px-3 py-1.5 min-h-[44px] rounded-lg text-xs font-medium bg-primary text-primary-content hover:bg-primary/80 transition-colors"
            >
              <.icon name="hero-plus" class="w-3.5 h-3.5" /> New Note
            </.link>
            <label
              :if={!@notes_select_mode && @notes != []}
              class="flex items-center gap-1.5 cursor-pointer text-xs text-base-content/40 hover:text-base-content/70 min-h-[44px] px-1 transition-colors"
              phx-click="enter_select_mode_notes"
            >
              <input type="checkbox" class="checkbox checkbox-sm checkbox-primary pointer-events-none" />
              Select
            </label>
          </div>
        </div>

        <.notes_list
          notes={@notes}
          starred_filter={@starred_filter}
          search_query={@search_query}
          sort_by={@notes_sort_by}
          type_filter={@type_filter}
          empty_id="project-notes-empty"
          editing_note_id={@editing_note_id}
          current_path={~p"/projects/#{@project.id}/notes"}
          selected_ids={@selected_note_ids}
          select_mode={@notes_select_mode}
        />
      </div>
    </div>

    <%!-- Quick Note Modal --%>
    <div
      :if={@show_quick_note_modal}
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
            <.icon name="hero-x-mark" class="w-4 h-4" />
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
            <.icon name="hero-star" class="w-3.5 h-3.5 text-warning/70" />
            <span class="text-sm text-base-content/70">Star this note</span>
          </label>
          <div class="flex justify-end gap-2 pt-1">
            <button type="button" phx-click="close_quick_note_modal" class="btn btn-ghost btn-sm">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary btn-sm">Create Note</button>
          </div>
        </form>
      </div>
      <div class="modal-backdrop bg-black/50" phx-click="close_quick_note_modal"></div>
    </div>
    """
  end
end
