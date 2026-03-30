defmodule EyeInTheSkyWeb.Components.NotesList do
  use Phoenix.Component
  import EyeInTheSkyWeb.CoreComponents
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [relative_time: 1]

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
    <div class="mb-5 flex items-center gap-3">
      <form phx-change="search" class="flex-1 sm:max-w-sm">
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
      <button
        type="button"
        phx-click="toggle_starred_filter"
        class={"flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all duration-150 " <>
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
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-0 h-8 text-xs"
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
          class="select select-xs bg-base-200/50 border-base-content/8 text-base-content/70 min-h-0 h-8 text-xs"
        >
          <option value="newest" selected={@sort_by == "newest"}>Newest</option>
          <option value="oldest" selected={@sort_by == "oldest"}>Oldest</option>
        </select>
      </form>
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
          <div class="py-1 flex items-start gap-1">
            <%!-- Collapse: title + body --%>
            <div class="collapse collapse-arrow flex-1 overflow-visible">
              <input type="checkbox" class="min-h-0 p-0" checked={note.id == @editing_note_id} />
              <div class="collapse-title py-2.5 px-0 min-h-0 flex flex-col gap-1">
                <div class="flex items-center gap-2">
                  <%= if note.starred == 1 do %>
                    <.icon name="hero-star-solid" class="w-3.5 h-3.5 text-warning flex-shrink-0" />
                  <% end %>
                  <span class="text-sm font-medium text-base-content/85 truncate">
                    {note.title || extract_title(note.body)}
                  </span>
                </div>
                <div class="flex items-center gap-1.5 text-xs text-base-content/40">
                  <span class={[
                    "inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium",
                    parent_type_class(note.parent_type)
                  ]}>
                    <.icon name={parent_type_icon(note.parent_type)} class="w-2.5 h-2.5" />
                    {parent_type_label(note.parent_type)}
                  </span>
                  <span class="text-base-content/20">&middot;</span>
                  <span class="tabular-nums">{relative_time(note.created_at)}</span>
                </div>
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
            <%!-- Action buttons outside collapse so they don't trigger open/close --%>
            <div class="flex items-center gap-0.5 flex-shrink-0 pt-2.5">
              <button
                type="button"
                phx-click="toggle_star"
                phx-value-note_id={note.id}
                class="flex items-center gap-1 text-xs text-base-content/30 hover:text-warning transition-colors px-1 py-0.5"
                aria-label={if note.starred == 1, do: "Unstar note", else: "Star note"}
                aria-pressed={note.starred == 1}
              >
                <.icon
                  name={if note.starred == 1, do: "hero-star-solid", else: "hero-star"}
                  class={"w-3.5 h-3.5 #{if note.starred == 1, do: "text-warning", else: ""}"}
                />
              </button>
              <button
                type="button"
                phx-click="edit_note"
                phx-value-note_id={note.id}
                class="flex items-center gap-1 text-xs text-base-content/30 hover:text-primary transition-colors px-1 py-0.5"
                aria-label="Edit note"
              >
                <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
              </button>
              <.link
                navigate={"/notes/#{note.id}/edit?return_to=#{URI.encode_www_form(@current_path)}"}
                class="flex items-center gap-1 text-xs text-base-content/30 hover:text-secondary transition-colors px-1 py-0.5"
                aria-label="Open full editor"
              >
                <.icon name="hero-arrows-pointing-out" class="w-3.5 h-3.5" />
              </.link>
              <button
                type="button"
                phx-click="delete_note"
                phx-value-note_id={note.id}
                data-confirm="Delete this note?"
                class="flex items-center gap-1 text-xs text-base-content/30 hover:text-error transition-colors px-1 py-0.5"
                aria-label="Delete note"
              >
                <.icon name="hero-trash" class="w-3.5 h-3.5" />
              </button>
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

  defp parent_type_label(type) when type in ["session", "sessions"], do: "Session"
  defp parent_type_label(type) when type in ["agent", "agents"], do: "Agent"
  defp parent_type_label(type) when type in ["project", "projects"], do: "Project"
  defp parent_type_label(type) when type in ["task", "tasks"], do: "Task"
  defp parent_type_label(type) when is_binary(type), do: String.capitalize(type)
  defp parent_type_label(_), do: "Note"

  defp parent_type_icon(type) when type in ["session", "sessions"], do: "hero-clock-mini"
  defp parent_type_icon(type) when type in ["agent", "agents"], do: "hero-cpu-chip-mini"
  defp parent_type_icon(type) when type in ["project", "projects"], do: "hero-folder-mini"

  defp parent_type_icon(type) when type in ["task", "tasks"],
    do: "hero-clipboard-document-list-mini"

  defp parent_type_icon(_), do: "hero-document-text-mini"

  defp parent_type_class(type) when type in ["session", "sessions"],
    do: "bg-info/10 text-info/70"

  defp parent_type_class(type) when type in ["agent", "agents"],
    do: "bg-primary/10 text-primary/70"

  defp parent_type_class(type) when type in ["project", "projects"],
    do: "bg-success/10 text-success/70"

  defp parent_type_class(_), do: "bg-base-content/[0.06] text-base-content/50"

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

  def format_date(nil), do: ""

  def format_date(timestamp) when is_binary(timestamp) do
    case NaiveDateTime.from_iso8601(timestamp) do
      {:ok, ndt} ->
        format_naive_date(ndt)

      _ ->
        case String.split(timestamp, [" ", "T"], parts: 2) do
          [date | _] -> date
          _ -> timestamp
        end
    end
  end

  def format_date(_), do: ""

  defp format_naive_date(ndt) do
    today = Date.utc_today()
    date = NaiveDateTime.to_date(ndt)

    cond do
      Date.compare(date, today) == :eq ->
        Calendar.strftime(ndt, "Today at %H:%M")

      Date.compare(date, Date.add(today, -1)) == :eq ->
        "Yesterday"

      Date.diff(today, date) < 7 ->
        Calendar.strftime(ndt, "%a %b %d")

      true ->
        Calendar.strftime(ndt, "%b %d, %Y")
    end
  end
end
