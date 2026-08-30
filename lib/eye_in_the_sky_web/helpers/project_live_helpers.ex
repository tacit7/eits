defmodule EyeInTheSkyWeb.Helpers.ProjectLiveHelpers do
  @moduledoc """
  Shared mount logic for project LiveViews.

  All project LiveViews share a common pattern: parse the project ID from params,
  load the project, assign sidebar state and page title, and handle the not-found case.
  This module extracts that pattern into a single reusable function.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, put_flash: 3]

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

  On invalid/missing project, puts an error flash and assigns nil values.

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
      |> assign(:palette_projects, palette_projects())
    else
      socket
      |> assign(:project, nil)
      |> assign(:project_id, nil)
      |> assign(:page_title, "Project Not Found")
      |> assign(:sidebar_tab, sidebar_tab)
      |> assign(:sidebar_project, nil)
      |> put_flash(:error, "Project not found")
    end
  end

  @doc """
  Loads a project for a project route.

  Project routes are the source of truth for the active workspace. This allows
  direct navigation and command-palette jumps to projects outside the currently
  selected workspace while still updating the rail/palette scope to match the
  routed project.
  """
  def load_project_for_socket(socket, project_id, preload \\ [])

  def load_project_for_socket(socket, project_id, preload) when not is_nil(project_id) do
    case Projects.get_project(project_id) do
      {:ok, project} ->
        maybe_preload_project(socket, project, preload)

      {:error, :not_found} ->
        nil
    end
  end

  def load_project_for_socket(_socket, _project_id, _preload), do: nil

  defp maybe_preload_project(socket, project, preload) do
    if preload != [] and connected?(socket),
      do: Projects.preload_project(project, preload),
      else: project
  end

  defp palette_projects do
    Projects.list_projects_for_sidebar()
    |> Enum.map(&%{id: &1.id, name: &1.name})
  end
end
