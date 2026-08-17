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
      socket
      |> assign(:project, project)
      |> assign(:project_id, project_id)
      |> assign(:page_title, "#{page_title_prefix} - #{project.name}")
      |> assign(:sidebar_tab, sidebar_tab)
      |> assign(:sidebar_project, project)
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
  Loads a project only when it belongs to the current user's default workspace.

  Returns nil when the project is invalid, missing, or outside the workspace.
  """
  def load_project_for_socket(socket, project_id, preload \\ []) do
    with project_id when not is_nil(project_id) <- project_id,
         workspace when not is_nil(workspace) <- workspace_for_socket(socket),
         {:ok, project} <- Projects.get_project(project_id),
         true <- project.workspace_id == workspace.id do
      if preload != [] and connected?(socket),
        do: Projects.preload_project(project, preload),
        else: project
    else
      _ -> nil
    end
  end

  defp workspace_for_socket(%{assigns: %{current_user: user}}) when not is_nil(user) do
    Workspaces.default_workspace_for_user(user)
  end

  defp workspace_for_socket(_socket), do: nil
end
