defmodule EyeInTheSkyWeb.Helpers.ProjectLiveHelpers do
  @moduledoc """
  Shared mount logic for project LiveViews.

  All project LiveViews share a common pattern: parse the project ID from params,
  load the project, assign sidebar state and page title, and handle the not-found case.
  This module extracts that pattern into a single reusable function.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EyeInTheSky.Projects
  alias EyeInTheSky.Repo
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
    project = if project_id, do: (case Projects.get_project(project_id) do
      {:ok, p} -> p
      {:error, :not_found} -> nil
    end), else: nil
    project = if project && preload != [], do: Repo.preload(project, preload), else: project

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
      |> put_flash(:error, "Invalid project ID")
    end
  end
end
