defmodule EyeInTheSkyWebWeb.NoteLive.Edit do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Notes

  @valid_return_paths ["/notes", ~r|^/projects/\d+/notes$|]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:note, nil)
      |> assign(:return_to, "/notes")
      |> assign(:saved, false)
      |> assign(:saved_timer, nil)
      |> assign(:sidebar_tab, :notes)
      |> assign(:sidebar_project, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    if socket.assigns.saved_timer do
      Process.cancel_timer(socket.assigns.saved_timer)
    end

    case Integer.parse(id) do
      {int_id, ""} ->
        case Notes.get_note(int_id) do
          nil ->
            socket =
              socket
              |> put_flash(:error, "Note not found.")
              |> push_navigate(to: "/notes")

            {:noreply, socket}

          note ->
            return_to = safe_return_to(params["return_to"])

            socket =
              socket
              |> assign(:note, note)
              |> assign(:return_to, return_to)
              |> assign(:saved, false)
              |> assign(:saved_timer, nil)
              |> assign(:page_title, "Edit Note")

            {:noreply, socket}
        end

      _ ->
        socket =
          socket
          |> put_flash(:error, "Invalid note ID.")
          |> push_navigate(to: "/notes")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("note_saved", %{"body" => body}, socket) do
    case Notes.update_note(socket.assigns.note, %{body: body}) do
      {:ok, updated_note} ->
        if socket.assigns.saved_timer do
          Process.cancel_timer(socket.assigns.saved_timer)
        end

        timer = Process.send_after(self(), :clear_saved, 3000)

        socket =
          socket
          |> assign(:note, updated_note)
          |> assign(:saved, true)
          |> assign(:saved_timer, timer)

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save note.")}
    end
  end

  @impl true
  def handle_event("update_title", %{"title" => title}, socket) do
    trimmed = String.trim(title)

    if trimmed == "" do
      {:noreply, socket}
    else
      case Notes.update_note(socket.assigns.note, %{title: trimmed}) do
        {:ok, updated_note} ->
          {:noreply, assign(socket, :note, updated_note)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update title.")}
      end
    end
  end

  @impl true
  def handle_info(:clear_saved, socket) do
    {:noreply, assign(socket, saved: false, saved_timer: nil)}
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
          name="title"
          value={@note.title || ""}
          placeholder="Untitled note"
          phx-blur="update_title"
          class="flex-1 bg-transparent border-none outline-none text-sm font-semibold text-base-content/90 placeholder:text-base-content/30 min-w-0 px-1 rounded focus:bg-base-200/40"
        />

        <%= if @note.parent_type do %>
          <span class={[
            "hidden sm:inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium flex-shrink-0",
            parent_type_class(@note.parent_type)
          ]}>
            <.icon name={parent_type_icon(@note.parent_type)} class="w-2.5 h-2.5" />
            <%= parent_type_label(@note.parent_type) %><%= context_suffix(@note) %>
          </span>
        <% end %>

        <button
          type="button"
          id="note-save-btn"
          class={[
            "flex items-center gap-1.5 text-xs font-medium px-3 py-1.5 rounded-md transition-all flex-shrink-0",
            if(@saved,
              do: "bg-success/10 text-success border border-success/30",
              else: "bg-primary text-primary-content hover:bg-primary/80"
            )
          ]}
        >
          <%= if @saved do %>
            <.icon name="hero-check" class="w-3.5 h-3.5" /> Saved
          <% else %>
            Save <kbd class="text-[9px] opacity-70 ml-0.5">⌘S</kbd>
          <% end %>
        </button>
      </div>

      <%!-- Editor area --%>
      <div class="flex flex-1 overflow-hidden">
        <div
          id={"note-full-editor-#{@note.id}"}
          phx-hook="NoteFullEditor"
          data-body={@note.body || ""}
          data-return-to={@return_to}
          class="flex-1 overflow-hidden"
        ></div>
      </div>

      <%!-- Status bar --%>
      <div class="flex items-center justify-between px-4 py-1 border-t border-base-content/8 bg-base-100 flex-shrink-0 text-[10px] text-base-content/35">
        <div class="flex items-center gap-4">
          <span class="flex items-center gap-1">
            <span class="w-1.5 h-1.5 rounded-full bg-success inline-block"></span>
            Markdown
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

  defp safe_return_to(path) when is_binary(path) do
    if String.starts_with?(path, "/") and
         Enum.any?(@valid_return_paths, fn
           p when is_binary(p) -> p == path
           r -> Regex.match?(r, path)
         end),
       do: path,
       else: "/notes"
  end

  defp safe_return_to(_), do: "/notes"

  defp context_suffix(note) do
    case note.parent_type do
      t when t in ["session", "sessions"] ->
        " · #{String.slice(note.parent_id || "", 0, 8)}"

      t when t in ["task", "tasks"] ->
        " · ##{note.parent_id}"

      _ ->
        ""
    end
  end

  defp parent_type_label(type) when type in ["session", "sessions"], do: "Session"
  defp parent_type_label(type) when type in ["agent", "agents"], do: "Agent"
  defp parent_type_label(type) when type in ["project", "projects"], do: "Project"
  defp parent_type_label(type) when type in ["task", "tasks"], do: "Task"
  defp parent_type_label(type) when is_binary(type), do: String.capitalize(type)
  defp parent_type_label(_), do: "Note"

  defp parent_type_icon(type) when type in ["session", "sessions"], do: "hero-clock-mini"
  defp parent_type_icon(type) when type in ["agent", "agents"], do: "hero-cpu-chip-mini"
  defp parent_type_icon(type) when type in ["project", "projects"], do: "hero-folder-mini"
  defp parent_type_icon(type) when type in ["task", "tasks"], do: "hero-clipboard-document-list-mini"
  defp parent_type_icon(_), do: "hero-document-text-mini"

  defp parent_type_class(type) when type in ["session", "sessions"],
    do: "bg-info/[0.08] text-info/70"

  defp parent_type_class(type) when type in ["agent", "agents"],
    do: "bg-secondary/[0.08] text-secondary/70"

  defp parent_type_class(type) when type in ["project", "projects"],
    do: "bg-primary/[0.08] text-primary/70"

  defp parent_type_class(_), do: "bg-base-content/[0.06] text-base-content/50"
end
