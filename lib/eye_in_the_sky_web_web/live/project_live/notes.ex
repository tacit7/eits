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
    IO.inspect(params, label: "TOGGLE_STAR_PARAMS")

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

        base =
          from(n in EyeInTheSkyWeb.Notes.Note,
            where:
              (n.parent_type in ["project", "projects"] and n.parent_id == ^project_id_str) or
                (n.parent_type in ["agent", "agents"] and n.parent_id in ^agent_ids) or
                (n.parent_type in ["session", "sessions"] and n.parent_id in ^session_ids),
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
    <style>
      .collapse input[type="checkbox"] {
        position: absolute;
        opacity: 0;
      }
      .star-icon {
        cursor: pointer;
        transition: all 0.2s ease;
        z-index: 10;
        position: relative;
        background: none;
        border: none;
        padding: 0.25rem;
        border-radius: 0.25rem;
      }
      .star-icon:hover {
        transform: scale(1.15);
        background: rgba(0, 0, 0, 0.05);
      }
      .star-icon:active {
        transform: scale(1.05);
      }
    </style>
    <.live_component
      module={EyeInTheSkyWebWeb.Components.Navbar}
      id="navbar"
      current_project={@project}
    />

    <EyeInTheSkyWebWeb.Components.ProjectNav.render
      project={@project}
      tasks={@tasks}
      current_tab={:notes}
    />

    <div class="px-4 sm:px-6 lg:px-8 py-8">
      <div class="max-w-6xl mx-auto">
        <!-- Search + Filter -->
        <div class="mb-6 flex items-center gap-3">
          <form phx-change="search" class="flex-1">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search notes by content..."
              class="input input-bordered w-full"
              autocomplete="off"
            />
          </form>
          <button
            type="button"
            phx-click="toggle_starred_filter"
            class={"btn btn-sm gap-2 #{if @starred_filter, do: "btn-warning", else: "btn-ghost"}"}
          >
            <.icon
              name={if @starred_filter, do: "hero-star-solid", else: "hero-star"}
              class="w-4 h-4"
            />
            Starred
          </button>
        </div>

        <%= if length(@notes) > 0 do %>
          <!-- Notes Accordion -->
          <div class="join join-vertical w-full">
            <%= for note <- @notes do %>
              <div class="collapse collapse-arrow join-item border border-base-300">
                <!-- Collapse Title -->
                <input type="checkbox" />
                <div class="collapse-title bg-base-100 hover:bg-base-100/80 transition-colors">
                  <div class="flex items-center justify-between">
                    <label class="flex items-center gap-3 flex-1 cursor-pointer">
                      <.icon name="hero-document-text" class="w-4 h-4 text-base-content/60 flex-shrink-0" />
                      <div class="flex flex-col gap-1">
                        <h3 class="font-semibold text-sm text-base-content">
                          {note.title || extract_title(note.body)}
                        </h3>
                        <div class="flex items-center gap-2 text-xs text-base-content/60">
                          <span class="font-mono">{String.slice(note.parent_id, 0..7)}</span>
                          <span>•</span>
                          <span>{format_timestamp(note.created_at)}</span>
                        </div>
                      </div>
                    </label>
                    <button
                      type="button"
                      class="star-icon"
                      phx-click="toggle_star"
                      phx-value-note_id={note.id}
                      onclick="event.stopPropagation(); event.preventDefault();"
                    >
                      <.icon
                        name={if note.starred == 1, do: "hero-star-solid", else: "hero-star"}
                        class={"w-5 h-5 #{if note.starred == 1, do: "text-warning", else: "text-base-content/40"}"}
                      />
                    </button>
                  </div>
                </div>
                
    <!-- Collapse Content -->
                <div class="collapse-content bg-base-50">
                  <div
                    id={"note-body-#{note.id}"}
                    class="dm-markdown text-sm text-base-content leading-relaxed"
                    phx-hook="MarkdownMessage"
                    data-raw-body={note.body}
                  ></div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <!-- Empty State -->
          <div class="text-center py-12">
            <.icon name="hero-document-text" class="mx-auto h-12 w-12 text-base-content/40" />
            <h3 class="mt-2 text-sm font-medium text-base-content">No notes yet</h3>
            <p class="mt-1 text-sm text-base-content/60">
              Notes from agents will appear here
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_timestamp(nil), do: ""

  defp format_timestamp(timestamp) when is_binary(timestamp) do
    # Timestamp is stored as string, just display it as-is or format as needed
    timestamp
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
