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

    notes =
      if query != "" and String.trim(query) != "" do
        Notes.search_notes(query, agent_ids)
      else
        from(n in EyeInTheSkyWeb.Notes.Note,
          where:
            (n.parent_type in ["agent", "agents"] and n.parent_id in ^agent_ids) or
              (n.parent_type in ["session", "sessions"] and n.parent_id in ^session_ids),
          order_by: [desc: n.created_at]
        )
        |> Repo.all()
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
        <!-- Search Input -->
        <div class="mb-6">
          <form phx-change="search" class="w-full">
            <input
              type="text"
              name="query"
              value={@search_query}
              placeholder="Search notes by content..."
              class="input input-bordered w-full"
              autocomplete="off"
            />
          </form>
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
                  <pre
                    id={"note-highlight-#{note.id}"}
                    phx-hook="Highlight"
                    class="whitespace-pre-wrap text-sm text-base-content p-0 font-mono leading-relaxed"
                  ><code class="language-plaintext"><%= note.body %></code></pre>
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
    |> String.slice(0..50)
    |> then(fn text ->
      if String.length(text) >= 50, do: text <> "...", else: text
    end)
  end
end
