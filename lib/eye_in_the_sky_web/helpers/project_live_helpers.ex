defmodule EyeInTheSkyWeb.Helpers.ProjectLiveHelpers do
  @moduledoc """
  Shared mount logic for project LiveViews.

  All project LiveViews share a common pattern: parse the project ID from params,
  load the project, assign sidebar state and page title, and handle the not-found case.
  This module extracts that pattern into a single reusable function.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  alias EyeInTheSky.Events
  alias EyeInTheSky.Projects
  alias EyeInTheSky.Workspaces
  import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [parse_id: 1]

  @doc """
  Sets up the base project assigns on the socket.

  Parses the project ID from `params["id"]`, loads the project, and assigns:
  - `:project` — the project struct (or nil if not found)
  - `:project_id` — the integer ID (or nil)
  - `:page_title` — "<prefix> - <project name>" or "Project Not Found"
  - `:sidebar_tab` — from opts
  - `:sidebar_project` — same as project (or nil)

  On invalid, missing, or foreign projects, raises `Ecto.NoResultsError` (404).

  ## Options
  - `:sidebar_tab` (required) — atom for the sidebar tab, e.g. `:tasks`
  - `:page_title_prefix` (required) — string prefix for the page title, e.g. `"Tasks"`
  - `:preload` — list of associations to preload, e.g. `[:agents]`
  """
  def mount_project(socket, %{"id" => id}, opts \\ []) do
    sidebar_tab = Keyword.fetch!(opts, :sidebar_tab)
    page_title_prefix = Keyword.fetch!(opts, :page_title_prefix)
    preload = Keyword.get(opts, :preload, [])

    project_id = parse_id(id)
    project = load_project_for_socket(socket, project_id, preload)

    if project do
      workspace = Workspaces.get_workspace(project.workspace_id)

      socket
      |> assign(:project, project)
      |> assign(:project_id, project.id)
      |> assign(:page_title, "#{page_title_prefix} - #{project.name}")
      |> assign(:sidebar_tab, sidebar_tab)
      |> assign(:sidebar_project, project)
      |> assign(:workspace, workspace)
      |> assign(:workspace_id, workspace && workspace.id)
      |> assign(:palette_projects, palette_projects_for_socket(socket))
    else
      # Stop before downstream pages can interpret a nil project as global scope.
      raise Ecto.NoResultsError, queryable: EyeInTheSky.Projects.Project
    end
  end

  @doc """
  Loads a project for a project route.

  The current workspace must be resolved before fetching the project. Missing
  workspace context and foreign projects both follow the not-found path, so a
  route parameter cannot switch the user's workspace.
  """
  def load_project_for_socket(socket, project_id, preload \\ [])

  def load_project_for_socket(socket, project_id, preload) when not is_nil(project_id) do
    workspace_id = Events.workspace_id_for_assigns(socket.assigns)

    case Projects.get_project_for_workspace(project_id, workspace_id) do
      {:ok, project} ->
        maybe_preload_project(socket, project, preload)

      {:error, :not_found} ->
        load_unscoped_project_for_auth_bypass(socket, project_id, preload)
    end
  end

  def load_project_for_socket(_socket, _project_id, _preload), do: nil

  defp load_unscoped_project_for_auth_bypass(socket, project_id, preload) do
    if auth_bypass_without_user?(socket) do
      case Projects.get_project(project_id) do
        {:ok, project} -> maybe_preload_project(socket, project, preload)
        {:error, :not_found} -> nil
      end
    end
  end

  defp auth_bypass_without_user?(socket) do
    Application.get_env(:eye_in_the_sky, :disable_auth, false) &&
      is_nil(socket.assigns[:current_user])
  end

  defp maybe_preload_project(socket, project, preload) do
    if preload != [] and connected?(socket),
      do: Projects.preload_project(project, preload),
      else: project
  end

  @doc "Returns active command-palette projects within the socket's workspace."
  def palette_projects_for_socket(socket) do
    case Events.workspace_id_for_assigns(socket.assigns) do
      nil ->
        []

      workspace_id ->
        workspace_id
        |> Projects.list_projects_for_workspace()
        |> Enum.filter(& &1.active)
        |> Enum.map(&%{id: &1.id, name: &1.name})
    end
  end
end
