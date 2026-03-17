defmodule EyeInTheSkyWebWeb.OverviewLive.Notes do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWeb.Notes.Note
  alias EyeInTheSkyWeb.Repo
  import Ecto.Query
  import EyeInTheSkyWebWeb.Components.NotesList
  import EyeInTheSkyWebWeb.Live.Shared.NotesHelpers

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "All Notes")
      |> assign(:search_query, "")
      |> assign(:starred_filter, false)
      |> assign(:notes, [])
      |> assign(:editing_note_id, nil)
      |> assign(:sidebar_tab, :notes)
      |> assign(:sidebar_project, nil)
      |> assign(:show_quick_note_modal, false)
      |> assign(:show_new_note_editor, false)
      |> load_notes()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", params, socket),
    do: handle_search(params, socket, &load_notes/1)

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
    {:noreply, assign(socket, :editing_note_id, String.to_integer(note_id))}
  end

  @impl true
  def handle_event("note_saved", %{"note_id" => note_id, "body" => body}, socket) do
    note = Notes.get_note!(String.to_integer(note_id))

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
    starred = if params["starred"] == "1", do: 1, else: 0

    case Notes.create_note(%{
           parent_type: "system",
           parent_id: "0",
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

  @impl true
  def handle_event("open_new_note_editor", _params, socket) do
    {:noreply, assign(socket, :show_new_note_editor, true)}
  end

  @impl true
  def handle_event("close_new_note_editor", _params, socket) do
    {:noreply, assign(socket, :show_new_note_editor, false)}
  end

  @impl true
  def handle_event("save_new_note", params, socket) do
    body = params["body"] || ""

    if String.trim(body) == "" do
      {:noreply, put_flash(socket, :error, "Note body cannot be empty")}
    else
      case Notes.create_note(%{
             parent_type: "system",
             parent_id: "0",
             title: params["title"] || "",
             body: body
           }) do
        {:ok, _note} ->
          {:noreply, socket |> assign(:show_new_note_editor, false) |> load_notes()}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to save note")}
      end
    end
  end

  defp load_notes(socket) do
    query = socket.assigns.search_query
    starred_only = socket.assigns.starred_filter

    notes =
      if query != "" and String.trim(query) != "" do
        Notes.search_notes(query, [], starred: starred_only)
      else
        base =
          from(n in Note,
            order_by: [desc: n.created_at],
            limit: 200
          )

        base = if starred_only, do: from(n in base, where: n.starred == 1), else: base
        Repo.all(base)
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
              All notes captured across projects and sessions
            </p>
          </div>
          <div class="flex items-center gap-2">
            <button
              type="button"
              phx-click="open_quick_note_modal"
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-base-200/60 hover:bg-base-200 text-base-content/70 hover:text-base-content transition-colors"
            >
              <.icon name="hero-bolt" class="w-3.5 h-3.5" /> Quick Note
            </button>
            <button
              type="button"
              phx-click="open_new_note_editor"
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-primary text-primary-content hover:bg-primary/80 transition-colors"
            >
              <.icon name="hero-plus" class="w-3.5 h-3.5" /> New Note
            </button>
          </div>
        </div>

        <%!-- Inline new note editor --%>
        <div :if={@show_new_note_editor} class="mb-5 rounded-xl border border-base-content/10 bg-base-100 overflow-hidden shadow-sm">
          <div class="flex items-center justify-between px-4 py-2.5 border-b border-base-content/8">
            <span class="text-sm font-semibold text-base-content/80">New Note</span>
            <button type="button" phx-click="close_new_note_editor" class="btn btn-ghost btn-xs btn-square" aria-label="Close">
              <.icon name="hero-x-mark" class="w-4 h-4" />
            </button>
          </div>
          <div class="px-4 pt-3">
            <input
              type="text"
              id="new-note-title-input"
              placeholder="Title (optional)..."
              class="input input-sm w-full bg-transparent border-base-content/10 focus:border-primary/30"
              autocomplete="off"
            />
          </div>
          <div
            id="inline-note-creator"
            phx-hook="InlineNoteCreator"
            phx-update="ignore"
            class="min-h-[220px] px-1"
          ></div>
          <div class="flex items-center justify-between px-4 py-2.5 border-t border-base-content/8">
            <span class="text-xs text-base-content/35">⌘S to save</span>
            <div class="flex gap-2">
              <button type="button" phx-click="close_new_note_editor" class="btn btn-ghost btn-xs">Cancel</button>
              <button type="button" id="inline-note-save-btn" class="btn btn-primary btn-xs">Save Note</button>
            </div>
          </div>
        </div>

        <.notes_list
          notes={@notes}
          starred_filter={@starred_filter}
          search_query={@search_query}
          empty_id="overview-notes-empty"
          editing_note_id={@editing_note_id}
          current_path="/notes"
        />
      </div>
    </div>

    <%!-- Quick Note Modal --%>
    <div :if={@show_quick_note_modal} class="modal modal-open" phx-window-keydown="close_quick_note_modal" phx-key="Escape">
      <div class="modal-box max-w-md p-0 overflow-hidden">
        <div class="flex items-center justify-between px-4 py-3 border-b border-base-content/10">
          <h2 class="text-sm font-semibold text-base-content">Quick Note</h2>
          <button type="button" phx-click="close_quick_note_modal" class="btn btn-ghost btn-xs btn-square" aria-label="Close">
            <.icon name="hero-x-mark" class="w-4 h-4" />
          </button>
        </div>
        <form phx-submit="create_quick_note" class="p-4 flex flex-col gap-3">
          <div>
            <label class="sr-only" for="qn-title">Title</label>
            <input
              type="text"
              name="title"
              id="qn-title"
              required
              placeholder="Title..."
              class="input input-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40"
              autocomplete="off"
              autofocus
            />
          </div>
          <div>
            <label class="sr-only" for="qn-body">Body</label>
            <textarea
              name="body"
              id="qn-body"
              rows="4"
              placeholder="Note content..."
              class="textarea textarea-sm w-full border-base-content/10 bg-base-100 focus:border-primary/40 resize-none"
            ></textarea>
          </div>
          <label class="flex items-center gap-2 cursor-pointer select-none">
            <input type="checkbox" name="starred" value="1" class="checkbox checkbox-sm" />
            <.icon name="hero-star" class="w-3.5 h-3.5 text-warning/70" />
            <span class="text-sm text-base-content/70">Star this note</span>
          </label>
          <div class="flex justify-end gap-2 pt-1">
            <button type="button" phx-click="close_quick_note_modal" class="btn btn-ghost btn-sm">Cancel</button>
            <button type="submit" class="btn btn-primary btn-sm">Create Note</button>
          </div>
        </form>
      </div>
      <div class="modal-backdrop bg-black/50" phx-click="close_quick_note_modal"></div>
    </div>
    """
  end
end
