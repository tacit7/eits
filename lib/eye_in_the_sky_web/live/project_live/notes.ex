defmodule EyeInTheSkyWeb.ProjectLive.Notes do
  use EyeInTheSkyWeb, :live_view

  alias EyeInTheSky.Notes
  alias EyeInTheSky.Projects
  import EyeInTheSkyWeb.Components.NotesList
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [parse_id: 1]
  import EyeInTheSkyWeb.Live.Shared.NotesHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project_id = parse_id(id)

    socket =
      if project_id do
        project =
          Projects.get_project_with_agents!(project_id)

        socket =
          socket
          |> assign(:page_title, "Notes - #{project.name}")
          |> assign(:project, project)
          |> assign(:sidebar_tab, :notes)
          |> assign(:sidebar_project, project)
          |> assign(:search_query, "")
          |> assign(:starred_filter, false)
          |> assign(:notes_sort_by, "newest")
          |> assign(:notes, [])
          |> assign(:editing_note_id, nil)
          |> assign(:show_quick_note_modal, false)
          |> assign(:type_filter, "all")

        if connected?(socket), do: load_notes(socket), else: socket
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:search_query, "")
        |> assign(:notes, [])
        |> assign(:editing_note_id, nil)
        |> put_flash(:error, "Invalid project ID")
      end

    {:ok, socket}
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
    project = socket.assigns.project
    agent_ids = Enum.map(project.agents, & &1.id)
    query = socket.assigns.search_query

    notes =
      if query != "" and String.trim(query) != "" do
        Notes.search_notes(query, agent_ids,
          project_id: project.id,
          starred: socket.assigns.starred_filter
        )
      else
        Notes.list_notes_filtered(
          project_id: project.id,
          agent_ids: agent_ids,
          starred: socket.assigns.starred_filter,
          sort: socket.assigns.notes_sort_by,
          type_filter: socket.assigns.type_filter
        )
      end

    assign(socket, :notes, notes)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 py-6">
      <div class="max-w-4xl mx-auto">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between mb-6">
          <div>
            <h1 class="text-lg font-semibold text-base-content/90">Notes</h1>
            <p class="text-xs text-base-content/50 mt-0.5">
              Notes captured by agents in this project
            </p>
          </div>
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
