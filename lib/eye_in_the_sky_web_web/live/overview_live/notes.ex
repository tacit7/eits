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
    """
  end
end
