defmodule EyeInTheSkyWebWeb.ProjectLive.Notes do
  use EyeInTheSkyWebWeb, :live_view

  alias EyeInTheSkyWeb.Projects
  alias EyeInTheSkyWeb.Notes
  alias EyeInTheSkyWeb.Repo
  import Ecto.Query
  import EyeInTheSkyWebWeb.Components.NotesList
  import EyeInTheSkyWebWeb.Helpers.ViewHelpers, only: [parse_id: 1]
  import EyeInTheSkyWebWeb.Live.Shared.NotesHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    project_id = parse_id(id)

    socket =
      if project_id do
        project =
          Projects.get_project!(project_id)
          |> Repo.preload([:agents])

        socket
        |> assign(:page_title, "Notes - #{project.name}")
        |> assign(:project, project)
        |> assign(:sidebar_tab, :notes)
        |> assign(:sidebar_project, project)
        |> assign(:search_query, "")
        |> assign(:starred_filter, false)
        |> assign(:notes, [])
        |> load_notes()
      else
        socket
        |> assign(:page_title, "Project Not Found")
        |> assign(:project, nil)
        |> assign(:search_query, "")
        |> assign(:notes, [])
        |> put_flash(:error, "Invalid project ID")
      end

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

  defp load_notes(socket) do
    project = socket.assigns.project
    agent_ids = Enum.map(project.agents, & &1.id)

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
      <div class="max-w-4xl mx-auto">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between mb-6">
          <div>
            <h1 class="text-lg font-semibold text-base-content/90">Notes</h1>
            <p class="text-xs text-base-content/50 mt-0.5">
              Notes captured by agents in this project
            </p>
          </div>
        </div>

        <.notes_list
          notes={@notes}
          starred_filter={@starred_filter}
          search_query={@search_query}
          empty_id="project-notes-empty"
        />
      </div>
    </div>
    """
  end
end
