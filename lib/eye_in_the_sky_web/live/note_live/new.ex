defmodule EyeInTheSkyWeb.NoteLive.New do
  use EyeInTheSkyWeb, :live_view

  import EyeInTheSkyWeb.NoteLive.Helpers, only: [safe_return_to: 1]

  alias EyeInTheSky.Notes

  @valid_parent_types ["session", "task", "agent", "project", "system"]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "New Note")
      |> assign(:title, "")
      |> assign(:parent_type, "system")
      |> assign(:parent_id, "0")
      |> assign(:return_to, "/notes")
      |> assign(:sidebar_tab, :notes)
      |> assign(:sidebar_project, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    parent_type =
      if params["parent_type"] in @valid_parent_types, do: params["parent_type"], else: "system"

    parent_id = params["parent_id"] || "0"
    return_to = safe_return_to(params["return_to"])

    {:noreply,
     socket
     |> assign(:parent_type, parent_type)
     |> assign(:parent_id, parent_id)
     |> assign(:return_to, return_to)}
  end

  @impl true
  def handle_event("update_title", %{"value" => title}, socket) do
    {:noreply, assign(socket, :title, String.trim(title))}
  end

  @impl true
  def handle_event("note_saved", %{"body" => body}, socket) do
    body = String.trim(body)

    if body == "" do
      {:noreply, put_flash(socket, :error, "Note body cannot be empty")}
    else
      case Notes.create_note(%{
             parent_type: socket.assigns.parent_type,
             parent_id: socket.assigns.parent_id,
             title: socket.assigns.title,
             body: body
           }) do
        {:ok, _note} ->
          {:noreply, push_navigate(socket, to: socket.assigns.return_to)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to create note")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-[calc(100vh-0px)] overflow-hidden">
      <%!-- Header --%>
      <div class="flex items-center gap-3 px-4 py-2.5 border-b border-base-content/8 bg-base-100 flex-shrink-0">
        <.link
          navigate={@return_to}
          class="flex items-center gap-1.5 text-xs text-base-content/40 hover:text-base-content/70 border border-base-content/10 rounded-md px-2.5 py-1.5 transition-colors flex-shrink-0"
        >
          <.icon name="hero-arrow-left" class="w-3.5 h-3.5" /> Notes
        </.link>

        <input
          type="text"
          id="note-title-input"
          name="title"
          placeholder="Untitled note"
          phx-blur="update_title"
          class="flex-1 bg-transparent border-none outline-none text-sm font-semibold text-base-content/90 placeholder:text-base-content/30 min-w-0 px-1 rounded focus:bg-base-200/40"
        />

        <button
          type="button"
          id="note-save-btn"
          class="flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-md transition-all flex-shrink-0 bg-primary text-primary-content hover:bg-primary/80"
        >
          Save <kbd class="text-xs opacity-70 ml-0.5">⌘S</kbd>
        </button>
      </div>

      <%!-- Editor area --%>
      <div class="flex flex-1 overflow-hidden">
        <div
          id="note-full-editor-new"
          phx-hook="NoteFullEditor"
          phx-update="ignore"
          data-body=""
          data-return-to={@return_to}
          class="flex-1 overflow-hidden"
        >
        </div>
      </div>

      <%!-- Status bar --%>
      <div class="flex items-center justify-between px-4 py-1 border-t border-base-content/8 bg-base-100 flex-shrink-0 text-xs text-base-content/35">
        <div class="flex items-center gap-4">
          <span class="flex items-center gap-1">
            <span class="w-1.5 h-1.5 rounded-full bg-success inline-block"></span> Markdown
          </span>
          <span id="note-editor-status">Ln 1, Col 1</span>
        </div>
        <div class="flex items-center gap-4">
          <span>Esc to go back</span>
          <span>⌘S to save</span>
        </div>
      </div>
    </div>
    """
  end

end
