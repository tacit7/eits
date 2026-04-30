defmodule EyeInTheSkyWeb.Components.Rail.Loader do
  @moduledoc """
  Data-loading helpers for the Rail live component.

  Each maybe_load_* function takes a socket and returns an updated socket.
  They are no-ops when the section argument doesn't match, so they can be
  piped unconditionally during section transitions.
  """

  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.{
    Canvases,
    Channels,
    Notes,
    ScheduledJobs,
    Sessions,
    Tasks,
    Teams
  }

  alias EyeInTheSky.Projects.FileTree
  alias EyeInTheSkyWeb.Live.Shared.AgentsHelpers

  @valid_sections ~w(sessions agents tasks prompts chat notes skills teams canvas notifications usage jobs files)
  @sticky_sections [:chat, :canvas]

  def parse_section(section_str) when section_str in @valid_sections,
    do: String.to_existing_atom(section_str)

  def parse_section(_), do: :sessions

  # Returns the section that should always remain visible for a given page tab.
  # nil means the flyout can be fully closed.
  def sticky_section(sidebar_tab) when sidebar_tab in [:canvas, :canvases], do: :canvas
  def sticky_section(:chat), do: :chat
  def sticky_section(_), do: nil

  def sticky_section?(section), do: section in @sticky_sections

  def parse_session_sort("created"), do: :created
  def parse_session_sort("name"), do: :name
  def parse_session_sort(_), do: :last_activity

  def parse_task_state("1"), do: 1
  def parse_task_state("2"), do: 2
  def parse_task_state("3"), do: 3
  def parse_task_state("4"), do: 4
  def parse_task_state(_), do: nil

  def load_flyout_sessions(project, sort \\ :last_activity, name_filter \\ "") do
    opts = [limit: 15, status_filter: "all", sort_by: sort]
    opts = if project, do: Keyword.put(opts, :project_id, project.id), else: opts
    opts = if name_filter != "", do: Keyword.put(opts, :name_filter, name_filter), else: opts

    case Sessions.list_sessions_filtered(opts) do
      sessions when is_list(sessions) -> sessions
      {:ok, sessions} when is_list(sessions) -> sessions
      _ -> []
    end
  end

  def load_flyout_tasks(project, search, state_id) do
    project_id = project && project.id
    state_opts = if state_id, do: [state_id: state_id], else: []

    cond do
      search != "" ->
        Tasks.search_tasks(search, project_id, [limit: 50] ++ state_opts)

      project_id ->
        Tasks.list_tasks_for_project(
          project_id,
          [limit: 50, sort_by: "created_desc"] ++ state_opts
        )

      true ->
        Tasks.list_tasks([limit: 50, sort_by: "created_desc"] ++ state_opts)
    end
  end

  def file_error_message(:root_path_not_found), do: "Project directory not found"
  def file_error_message(:root_path_not_directory), do: "Project path is not a directory"
  def file_error_message(:permission_denied), do: "Permission denied"
  def file_error_message(:path_not_found), do: "Directory not found"
  def file_error_message(:symlink_escapes_project), do: "Path escapes project root"
  def file_error_message(_), do: "Cannot read directory"

  # Load canvases (with sessions) only when navigating to the :canvas section.
  def maybe_load_canvases(socket, :canvas) do
    canvases = Canvases.list_canvases_preloaded()

    session_ids =
      canvases
      |> Enum.flat_map(&Enum.map(&1.canvas_sessions, fn cs -> cs.session_id end))
      |> Enum.uniq()

    sessions_by_id =
      Sessions.list_sessions_by_ids(session_ids)
      |> Map.new(fn s -> {s.id, s} end)

    flyout_canvases =
      Enum.map(canvases, fn canvas ->
        sessions =
          canvas.canvas_sessions
          |> Enum.map(fn cs -> sessions_by_id[cs.session_id] end)
          |> Enum.reject(&is_nil/1)

        %{id: canvas.id, name: canvas.name, sessions: sessions}
      end)

    assign(socket, :flyout_canvases, flyout_canvases)
  end

  def maybe_load_canvases(socket, _section), do: socket

  def maybe_load_teams(socket, :teams, project) do
    opts = if project, do: [project_id: project.id], else: []
    assign(socket, :flyout_teams, Teams.list_teams(opts))
  end

  def maybe_load_teams(socket, _section, _project), do: socket

  def maybe_load_tasks(socket, :tasks, project) do
    tasks =
      load_flyout_tasks(
        project,
        socket.assigns[:task_search] || "",
        socket.assigns[:task_state_filter]
      )

    assign(socket, :flyout_tasks, tasks)
  end

  def maybe_load_tasks(socket, _section, _project), do: socket

  def maybe_load_jobs(socket, :jobs) do
    assign(socket, :flyout_jobs, ScheduledJobs.list_jobs() |> Enum.take(15))
  end

  def maybe_load_jobs(socket, _section), do: socket

  def maybe_load_notes(socket, :notes, project) do
    opts = [limit: 20]
    opts = if project, do: Keyword.put(opts, :project_id, project.id), else: opts
    assign(socket, :flyout_notes, Notes.list_notes_filtered(opts))
  end

  def maybe_load_notes(socket, _section, _project), do: socket

  def maybe_load_files(socket, :files) do
    project = socket.assigns.sidebar_project

    if project && project.path do
      case FileTree.root(project.path) do
        {:ok, nodes} ->
          socket
          |> assign(:flyout_file_nodes, nodes)
          |> assign(:flyout_file_error, nil)

        {:error, reason} ->
          socket
          |> assign(:flyout_file_nodes, [])
          |> assign(:flyout_file_error, file_error_message(reason))
      end
    else
      socket
      |> assign(:flyout_file_nodes, [])
      |> assign(:flyout_file_error, "No project path configured")
    end
  end

  def maybe_load_files(socket, _section), do: socket

  def maybe_load_agents(socket, :agents, project) do
    assign(socket, :flyout_agents, AgentsHelpers.list_agents_for_flyout(project))
  end

  def maybe_load_agents(socket, _section, _project), do: socket

  # Load channels only when navigating to the :chat section — avoids a DB query on every page.
  def maybe_load_channels(socket, :chat, project) do
    project_id = project && project.id

    channels =
      case Channels.list_channels_for_project(project_id) do
        list when is_list(list) -> list
        _ -> []
      end

    assign(socket, :flyout_channels, channels)
  end

  def maybe_load_channels(socket, _section, _project), do: socket
end
