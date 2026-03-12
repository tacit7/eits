defmodule EyeInTheSkyWebWeb.ProjectLive.Notes do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWeb.Repo
  import Ecto.Query

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    # Parse project ID safely
    project_id =
      case Integer.parse(id) do
        {int, ""} -> int
        _ -> nil
      end

    socket =
      if project_id do
        project =
          Projects.get_project!(project_id)
          |> Repo.preload([:agents])

        # Load tasks manually due to type mismatch
        tasks = Projects.get_project_tasks(project_id)

        socket
        |> assign(:page_title, "Notes - #{project.name}")
        |> assign(:project, project)
        |> assign(:sidebar_tab, :notes)
        |> assign(:sidebar_project, project)
        |> assign(:tasks, tasks)
        |> assign(:search_query, "")
        |> assign(:starred_filter, false)
        |> assign(:notes, [])
        |> load_notes()
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:tasks, [])
        |> assign(:search_query, "")
        |> assign(:notes, [])
        |> put_flash(:error, "Invalid project ID")
      end

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
    project = socket.assigns.project
    agent_ids = Enum.map(project.agents, & &1.id)

    # Get all session IDs for agents in this project
    session_ids =
      from(s in EyeInTheSkyWeb.Sessions.Session,
        where: s.agent_id in ^agent_ids,
        select: s.id
      )
      |> Repo.all()

    query = socket.assigns.search_query

    starred_only = socket.assigns.starred_filter

    notes =
      if query != "" and String.trim(query) != "" do
        results = Notes.search_notes(query, agent_ids)
        if starred_only, do: Enum.filter(results, &(&1.starred == 1)), else: results
      else
        project_id_str = to_string(project.id)
        agent_id_strs = Enum.map(agent_ids, &to_string/1)
        session_id_strs = Enum.map(session_ids, &to_string/1)

        base =
          from(n in EyeInTheSkyWeb.Notes.Note,
            where:
              (n.parent_type in ["project", "projects"] and n.parent_id == ^project_id_str) or
                (n.parent_type in ["agent", "agents"] and n.parent_id in ^agent_id_strs) or
                (n.parent_type in ["session", "sessions"] and
                   n.parent_id in ^session_id_strs),
            order_by: [desc: n.created_at]
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
          <div class="divide-y divide-base-content/5 bg-[oklch(97%_0.005_80)] dark:bg-[hsl(60,2.1%,18.4%)] rounded-xl shadow-sm px-5">
            <%= for note <- @notes do %>
              <div class="collapse collapse-arrow">
                <input type="checkbox" class="min-h-0 p-0" />
                <div class="collapse-title py-3.5 px-0 min-h-0 flex flex-col gap-1">
                  <span class="text-sm font-medium text-base-content/85 truncate pr-6">
                    {note.title || extract_title(note.body)}
                  </span>
                  <div class="flex items-center gap-1.5 text-xs text-base-content/35">
                    <span>{note.parent_type}</span>
                    <span class="text-base-content/15">&middot;</span>
                    <span class="font-mono tabular-nums">{format_date(note.created_at)}</span>
                    <%= if note.starred == 1 do %>
                      <span class="text-base-content/15">&middot;</span>
                      <.icon name="hero-star-solid" class="w-3 h-3 text-warning" />
                    <% end %>
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
                    class="mt-3 flex items-center gap-1.5 text-xs text-base-content/30 hover:text-warning transition-colors"
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
            id="project-notes-empty"
            icon="hero-document-text"
            title="No notes yet"
            subtitle="Notes from agents will appear here"
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp format_date(nil), do: ""

  defp format_date(timestamp) when is_binary(timestamp) do
    case String.split(timestamp, [" ", "T"], parts: 2) do
      [date | _] -> date
      _ -> timestamp
    end
  end

  defp extract_title(body) when is_nil(body), do: "Untitled"

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
end
