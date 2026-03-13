defmodule EyeInTheSkyWebWeb.OverviewLive.Notes do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWeb.Notes.Note
  alias EyeInTheSkyWeb.Repo
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "All Notes")
      |> assign(:search_query, "")
      |> assign(:starred_filter, false)
      |> assign(:notes, [])
      |> assign(:sidebar_tab, :notes)
      |> assign(:sidebar_project, nil)
      |> load_notes()

    {:ok, socket}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    effective_query = if String.length(String.trim(query)) >= 4, do: query, else: ""

    socket =
      socket
      |> assign(:search_query, effective_query)
      |> load_notes()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_starred_filter", _params, socket) do
    {:noreply,
     socket
     |> assign(:starred_filter, !socket.assigns.starred_filter)
     |> load_notes()}
  end

  @impl true
  def handle_event("toggle_star", params, socket) do
    note_id = params["note_id"] || params["note-id"] || params["value"]

    case Notes.toggle_starred(note_id) do
      {:ok, _note} ->
        {:noreply, load_notes(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to toggle star")}
    end
  end

  defp load_notes(socket) do
    query = socket.assigns.search_query
    starred_only = socket.assigns.starred_filter

    notes =
      if query != "" and String.trim(query) != "" do
        results = Notes.search_notes(query)
        if starred_only, do: Enum.filter(results, &(&1.starred == 1)), else: results
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
        <%!-- Page header --%>
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between mb-6">
          <div>
            <h1 class="text-lg font-semibold text-base-content/90">Notes</h1>
            <p class="text-xs text-base-content/50 mt-0.5">
              All notes captured across projects and sessions
            </p>
          </div>
        </div>

        <%!-- Search + Filter --%>
        <div class="mb-5 flex items-center gap-3">
          <form phx-change="search" class="flex-1 sm:max-w-sm">
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
              </div>
              <label for="overview-notes-search" class="sr-only">Search notes</label>
              <input
                type="text"
                name="query"
                id="overview-notes-search"
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
        </div>

        <%!-- Notes count --%>
        <div class="mb-3">
          <span class="text-[11px] font-mono tabular-nums text-base-content/45 tracking-wider uppercase">
            {length(@notes)} notes
          </span>
        </div>

        <%= if length(@notes) > 0 do %>
          <div class="divide-y divide-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm px-5">
            <%= for note <- @notes do %>
              <div class="collapse collapse-arrow">
                <input type="checkbox" class="min-h-0 p-0" />
                <div class="collapse-title py-3.5 px-0 min-h-0 flex flex-col gap-1">
                  <div class="flex items-center gap-2 pr-6">
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
                    <span class="font-mono tabular-nums">{format_date(note.created_at)}</span>
                  </div>
                </div>
                <div class="collapse-content px-0 pb-4">
                  <div
                    id={"note-body-#{note.id}"}
                    class="dm-markdown text-sm text-base-content/70 leading-relaxed"
                    phx-hook="MarkdownMessage"
                    data-raw-body={note.body}
                  >
                  </div>
                  <button
                    type="button"
                    phx-click="toggle_star"
                    phx-value-note_id={note.id}
                    class="mt-3 flex items-center gap-1.5 text-xs text-base-content/30 hover:text-warning transition-colors min-h-[44px] md:min-h-0 px-1"
                    aria-label={if note.starred == 1, do: "Unstar note", else: "Star note"}
                    aria-pressed={note.starred == 1}
                  >
                    <.icon
                      name={if note.starred == 1, do: "hero-star-solid", else: "hero-star"}
                      class={"w-3.5 h-3.5 #{if note.starred == 1, do: "text-warning", else: ""}"}
                    />
                    {if note.starred == 1, do: "Starred", else: "Star"}
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <.empty_state
            id="overview-notes-empty"
            icon="hero-document-text"
            title="No notes yet"
            subtitle="Notes from agents will appear here"
          />
        <% end %>
      </div>
    </div>
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
  defp parent_type_icon(type) when type in ["task", "tasks"], do: "hero-clipboard-document-list-mini"
  defp parent_type_icon(_), do: "hero-document-text-mini"

  defp parent_type_class(type) when type in ["session", "sessions"],
    do: "bg-info/10 text-info/70"

  defp parent_type_class(type) when type in ["agent", "agents"],
    do: "bg-primary/10 text-primary/70"

  defp parent_type_class(type) when type in ["project", "projects"],
    do: "bg-success/10 text-success/70"

  defp parent_type_class(_), do: "bg-base-content/[0.06] text-base-content/50"

  defp extract_title(nil), do: "Untitled"

  defp extract_title(body) when is_binary(body) do
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

  defp format_date(nil), do: ""

  defp format_date(timestamp) when is_binary(timestamp) do
    case NaiveDateTime.from_iso8601(timestamp) do
      {:ok, ndt} -> format_naive_date(ndt)
      _ ->
        case String.split(timestamp, [" ", "T"], parts: 2) do
          [date | _] -> date
          _ -> timestamp
        end
    end
  end

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
