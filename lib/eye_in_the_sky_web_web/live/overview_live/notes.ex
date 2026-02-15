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
    <div class="px-6 lg:px-8 py-6">
      <div class="max-w-3xl mx-auto">
        <%!-- Search + Filter --%>
        <div class="mb-5 flex items-center gap-3">
          <form phx-change="search" class="flex-1 max-w-sm">
            <div class="relative">
              <div class="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3">
                <.icon name="hero-magnifying-glass-mini" class="w-4 h-4 text-base-content/25" />
              </div>
              <input
                type="text"
                name="query"
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
            class={"flex items-center gap-1.5 px-3 py-1 rounded-lg text-xs font-medium transition-all duration-150 " <>
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
          <span class="text-[11px] font-mono tabular-nums text-base-content/30 tracking-wider uppercase">
            {length(@notes)} notes
          </span>
        </div>

        <%= if length(@notes) > 0 do %>
          <div class="space-y-1 bg-[oklch(95%_0.003_80)] dark:bg-[oklch(18%_0.005_260)] rounded-xl shadow-sm p-3">
            <%= for note <- @notes do %>
              <div class="collapse collapse-arrow rounded-lg border border-base-content/5 bg-white dark:bg-[oklch(22%_0.005_260)] hover:border-base-content/10 transition-colors">
                <input type="checkbox" />
                <div class="collapse-title py-2.5 px-4 min-h-0">
                  <div class="flex items-center gap-3">
                    <%!-- Star button --%>
                    <button
                      type="button"
                      phx-click="toggle_star"
                      phx-value-note_id={note.id}
                      onclick="event.stopPropagation(); event.preventDefault();"
                      class="flex-shrink-0 p-0.5 rounded transition-transform hover:scale-110"
                    >
                      <.icon
                        name={if note.starred == 1, do: "hero-star-solid", else: "hero-star"}
                        class={"w-3.5 h-3.5 #{if note.starred == 1, do: "text-warning", else: "text-base-content/15 hover:text-base-content/30"}"}
                      />
                    </button>
                    <%!-- Title --%>
                    <div class="flex-1 min-w-0">
                      <h3 class="text-[13px] font-medium text-base-content/85 truncate">
                        {note.title || extract_title(note.body)}
                      </h3>
                    </div>
                    <%!-- Meta inline --%>
                    <span class="hidden sm:inline-block flex-shrink-0 px-1.5 py-0.5 rounded text-[10px] font-medium bg-base-content/[0.05] text-base-content/40">
                      {note.parent_type}
                    </span>
                    <span class="hidden md:block flex-shrink-0 text-[11px] text-base-content/25 font-mono tabular-nums">
                      {format_date(note.created_at)}
                    </span>
                  </div>
                </div>
                <div class="collapse-content px-4 pb-4">
                  <div class="pl-[30px]">
                    <div
                      id={"note-body-#{note.id}"}
                      class="dm-markdown text-sm text-base-content/70 leading-relaxed"
                      phx-hook="MarkdownMessage"
                      data-raw-body={note.body}
                    >
                    </div>
                  </div>
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
    # Extract just the date portion from various timestamp formats
    case String.split(timestamp, [" ", "T"], parts: 2) do
      [date | _] -> date
      _ -> timestamp
    end
  end
end
