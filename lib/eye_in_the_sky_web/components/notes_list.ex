defmodule EyeInTheSkyWeb.Components.NotesList do
  @moduledoc false
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1]
  import EyeInTheSkyWeb.ControllerHelpers, only: [normalize_parent_type: 1]

  attr :notes, :list, required: true
  attr :starred_filter, :boolean, default: false
  attr :search_query, :string, default: ""
  attr :sort_by, :string, default: "newest"
  attr :type_filter, :string, default: "all"
  attr :empty_id, :string, default: "notes-empty"
  attr :editing_note_id, :integer, default: nil
  attr :current_path, :string, default: "/notes"

  def notes_list(assigns) do
    ~H"""
    <%!-- Search + Filter --%>
    <div class="mb-5 flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center sm:gap-3">
      <form phx-change="search" class="w-full sm:flex-1 sm:max-w-sm">
        <div class="relative">
          <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
            <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
          </div>
          <label for={"#{@empty_id}-search"} class="sr-only">Search notes</label>
          <input
            type="text"
            name="query"
            id={"#{@empty_id}-search"}
            value={@search_query}
            placeholder="Search notes..."
            class="input input-sm w-full pl-9 bg-base-200/50 border-base-content/8 placeholder:text-base-content/25 focus:border-primary/30 focus:bg-base-100 transition-colors text-sm"
            autocomplete="off"
          />
        </div>
      </form>
      <div class="flex items-center gap-2">
        <button
          type="button"
          phx-click="toggle_starred_filter"
          class={"flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all duration-150 min-h-[44px] min-w-[44px] " <>
            if(@starred_filter,
              do: "bg-warning/10 text-warning",
              else: "text-base-content/35 hover:text-base-content/50 hover:bg-base-200/40"
            )}
        >
          <.icon
            name={if @starred_filter, do: "hero-star-solid", else: "hero-star"}
            class="w-3.5 h-3.5"
          /> Starred
        </button>
        <form phx-change="filter_type">
          <label for={"#{@empty_id}-type"} class="sr-only">Filter by type</label>
          <select
            name="value"
            id={"#{@empty_id}-type"}
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
          <label for={"#{@empty_id}-sort"} class="sr-only">Sort notes</label>
          <select
            name="value"
            id={"#{@empty_id}-sort"}
            class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-[44px] text-xs"
          >
            <option value="newest" selected={@sort_by == "newest"}>Newest</option>
            <option value="oldest" selected={@sort_by == "oldest"}>Oldest</option>
          </select>
        </form>
      </div>
    </div>

    <%!-- Notes count --%>
    <div class="mb-3">
      <span class="text-[11px] font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
        {length(@notes)} notes
      </span>
    </div>

    <%= if length(@notes) > 0 do %>
      <div class="divide-y divide-base-content/5 bg-base-100 rounded-xl shadow-sm px-5">
        <%= for note <- @notes do %>
          <div class="py-1 flex items-start gap-1 group">
            <%!-- Collapse: chevron expands inline body --%>
            <div class="collapse flex-1 overflow-visible">
              <input type="checkbox" class="min-h-0 p-0" checked={note.id == @editing_note_id} />
              <div class="collapse-title py-3 px-0 min-h-0 flex flex-col gap-1">
                <%!-- Title — clicking navigates to full editor --%>
                <div class="flex items-center gap-2 pr-6">
                  <%= if starred?(note) do %>
                    <.icon name="hero-star-solid" class="w-3 h-3 text-warning flex-shrink-0" />
                  <% end %>
                  <.link
                    navigate={"/notes/#{note.id}/edit?return_to=#{URI.encode_www_form(@current_path)}"}
                    class="text-sm font-medium text-base-content/85 hover:text-base-content truncate"
                  >
                    {note.title || extract_title(note.body)}
                  </.link>
                </div>
                <%!-- Metadata: type badge • source ref • age --%>
                <div class="flex items-center gap-1.5 text-[11px] text-base-content/40">
                  <span class={[
                    "inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium",
                    parent_type_class(note.parent_type)
                  ]}>
                    <.icon name={parent_type_icon(note.parent_type)} class="w-2.5 h-2.5" />
                    {parent_type_label(note.parent_type)}
                  </span>
                  <%= if ref = format_parent_ref(note.parent_id) do %>
                    <span class="text-base-content/20">&middot;</span>
                    <span class="font-mono text-base-content/30">{ref}</span>
                  <% end %>
                  <span class="text-base-content/20">&middot;</span>
                  <span class="tabular-nums">{relative_time(note.created_at)}</span>
                </div>
                <%!-- Snippet preview --%>
                <%= if snippet = extract_snippet(note.body) do %>
                  <p class="text-xs text-base-content/35 truncate leading-snug mt-0.5 pr-6">
                    {snippet}
                  </p>
                <% end %>
              </div>
              <div class="collapse-content px-0 pb-2">
                <%= if note.id == @editing_note_id do %>
                  <div
                    id={"note-editor-#{note.id}"}
                    phx-hook="NoteEditor"
                    data-note-id={note.id}
                    data-body={Base.encode64(note.body || "")}
                    class="border border-base-content/10 rounded-lg overflow-hidden min-h-[200px] mb-2"
                  >
                  </div>
                  <div class="mb-2 flex items-center gap-3">
                    <span class="text-xs text-base-content/40">⌘S to save</span>
                    <button
                      type="button"
                      phx-click="note_edit_cancelled"
                      phx-value-note_id={note.id}
                      class="flex items-center gap-1.5 text-xs text-base-content/30 hover:text-base-content/60 transition-colors px-1"
                    >
                      Cancel
                    </button>
                  </div>
                <% else %>
                  <div
                    id={"note-body-#{note.id}"}
                    class="dm-markdown text-sm text-base-content/70 leading-relaxed pb-2"
                    phx-hook="MarkdownMessage"
                    data-raw-body={note.body}
                  >
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Right: star always visible, kebab on hover --%>
            <div class="flex items-center gap-0.5 flex-shrink-0 pt-3">
              <button
                type="button"
                phx-click="toggle_star"
                phx-value-note_id={note.id}
                class={"flex items-center px-1 py-1 rounded transition-colors " <>
                  if(starred?(note),
                    do: "text-warning",
                    else: "text-base-content/20 hover:text-warning"
                  )}
                aria-label={if starred?(note), do: "Unstar note", else: "Star note"}
              >
                <.icon
                  name={if starred?(note), do: "hero-star-solid", else: "hero-star"}
                  class="w-3.5 h-3.5"
                />
              </button>
              <div class="dropdown dropdown-end">
                <button
                  tabindex="0"
                  role="button"
                  class="flex items-center px-1 py-1 rounded text-base-content/20 hover:text-base-content/60 hover:bg-base-200/50 transition-colors sm:opacity-0 sm:group-hover:opacity-100"
                  aria-label="More actions"
                >
                  <.icon name="hero-ellipsis-vertical" class="w-4 h-4" />
                </button>
                <ul
                  tabindex="0"
                  class="dropdown-content z-50 menu menu-xs p-1 shadow-lg bg-base-200 rounded-lg w-44 border border-base-content/8"
                >
                  <li>
                    <button
                      type="button"
                      phx-click="edit_note"
                      phx-value-note_id={note.id}
                      class="flex items-center gap-2 text-xs"
                    >
                      <.icon name="hero-pencil-square" class="w-3.5 h-3.5" /> Edit inline
                    </button>
                  </li>
                  <li>
                    <.link
                      navigate={"/notes/#{note.id}/edit?return_to=#{URI.encode_www_form(@current_path)}"}
                      class="flex items-center gap-2 text-xs"
                    >
                      <.icon name="hero-arrows-pointing-out" class="w-3.5 h-3.5" /> Open full editor
                    </.link>
                  </li>
                  <li class="mt-1 border-t border-base-content/8 pt-1">
                    <button
                      type="button"
                      phx-click="delete_note"
                      phx-value-note_id={note.id}
                      data-confirm="Delete this note?"
                      class="flex items-center gap-2 text-xs text-error/70 hover:!text-error hover:!bg-error/10"
                    >
                      <.icon name="hero-trash" class="w-3.5 h-3.5" /> Delete
                    </button>
                  </li>
                </ul>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% else %>
      <.empty_state
        id={@empty_id}
        icon="hero-document-text"
        title="No notes yet"
        subtitle="Notes from agents will appear here"
      />
    <% end %>
    """
  end

  defp parent_type_label(type) do
    case normalize_parent_type(type) do
      "session" -> "Session"
      "agent" -> "Agent"
      "project" -> "Project"
      "task" -> "Task"
      t when is_binary(t) -> String.capitalize(t)
      _ -> "Note"
    end
  end

  defp parent_type_icon(type) do
    case normalize_parent_type(type) do
      "session" -> "hero-clock-mini"
      "agent" -> "hero-cpu-chip-mini"
      "project" -> "hero-folder-mini"
      "task" -> "hero-clipboard-document-list-mini"
      _ -> "hero-document-text-mini"
    end
  end

  defp parent_type_class(type) do
    case normalize_parent_type(type) do
      "session" -> "bg-info/10 text-info/70"
      "agent" -> "bg-primary/10 text-primary/70"
      "project" -> "bg-success/10 text-success/70"
      _ -> "bg-base-content/[0.06] text-base-content/50"
    end
  end

  # UUID (36 chars) -> first 8 chars; integer string -> "#N"; nil/empty -> nil
  defp format_parent_ref(nil), do: nil
  defp format_parent_ref(""), do: nil

  defp format_parent_ref(id) when is_binary(id) do
    if String.length(id) == 36 and String.contains?(id, "-") do
      String.slice(id, 0, 8)
    else
      "#" <> id
    end
  end

  def extract_title(nil), do: "Untitled"

  def extract_title(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split("\n")
    |> List.first()
    |> String.replace(~r/^#+\s*/, "")
    |> String.slice(0..50)
    |> then(fn text ->
      if String.length(text) >= 50, do: text <> "...", else: text
    end)
  end

  defp starred?(note), do: note.starred == true

  defp extract_snippet(nil), do: nil

  defp extract_snippet(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.split("\n")
    |> Enum.drop(1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn line ->
      line == "" or String.starts_with?(line, "#") or String.starts_with?(line, "---")
    end)
    |> List.first()
    |> case do
      nil ->
        nil

      line ->
        stripped =
          line
          |> String.replace(~r/^[-*+]\s+/, "")
          |> String.replace(~r/^\d+\.\s+/, "")
          |> String.replace(~r/\*\*(.+?)\*\*/, "\\1")
          |> String.replace(~r/\*(.+?)\*/, "\\1")
          |> String.replace(~r/`(.+?)`/, "\\1")
          |> String.replace(~r/\[(.+?)\]\(.+?\)/, "\\1")

        if String.length(stripped) > 0, do: String.slice(stripped, 0, 120), else: nil
    end
  end

end
