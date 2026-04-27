defmodule EyeInTheSkyWeb.Components.ScopeComponents do
  @moduledoc """
  UI components for communicating the active scope (workspace vs project)
  to the user. Used by workspace and project LiveViews.
  """

  use EyeInTheSkyWeb, :html

  alias EyeInTheSky.Scope

  # ---------------------------------------------------------------------------
  # scope_subtitle/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a small subtitle below a list title indicating the active scope.

  Project scope: "EITS Web only"
  Workspace scope: "Across all projects"
  """
  attr :scope, Scope, required: true

  def scope_subtitle(%{scope: %Scope{type: :project}} = assigns) do
    ~H"""
    <span class="text-xs text-base-content/50 font-normal">
      {@scope.project.name} only
    </span>
    """
  end

  def scope_subtitle(%{scope: %Scope{type: :workspace}} = assigns) do
    ~H"""
    <span class="text-xs text-base-content/50 font-normal">
      Across all projects
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # project_label/1
  # ---------------------------------------------------------------------------

  @doc """
  Compact project badge for workspace aggregate list rows.
  Hide it in project-scoped views where the project is already implicit.

  Usage:
    <.project_label project={@session.project} />
    or conditionally:
    <.project_label :if={Scope.workspace?(@scope)} project={@session.project} />
  """
  attr :project, :map, required: true

  def project_label(assigns) do
    ~H"""
    <span class="inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-base-200 text-base-content/60">
      {@project.name}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # context_switcher/1
  # ---------------------------------------------------------------------------

  @doc """
  DaisyUI details/summary dropdown for switching between workspace and project scope.

  Shows current context in the trigger. Workspace at top, then project list.
  Uses phx-update="ignore" with a stable id to preserve open state across LiveView patches.

  Usage:
    <.context_switcher scope={@scope} projects={@projects} />
  """
  attr :scope, Scope, required: true
  attr :projects, :list, required: true

  def context_switcher(assigns) do
    ~H"""
    <details id="context-switcher" phx-update="ignore" class="dropdown">
      <summary class="btn btn-ghost btn-sm gap-1.5 font-medium normal-case">
        <span class="text-sm leading-tight">
          <%= if Scope.project?(@scope) do %>
            {@scope.project.name}
            <span class="text-xs text-base-content/50 ml-1">Project</span>
          <% else %>
            {@scope.workspace.name}
            <span class="text-xs text-base-content/50 ml-1">All projects</span>
          <% end %>
        </span>
        <.icon name="hero-chevron-down" class="size-3 text-base-content/50" />
      </summary>
      <ul class="dropdown-content menu bg-base-100 border border-base-300 rounded-box shadow-sm w-56 z-50 p-1">
        <li class="menu-title text-xs text-base-content/40 px-2 pt-1">WORKSPACE</li>
        <li>
          <.link navigate={~p"/workspace/sessions"} class="gap-2 text-sm">
            <.icon name="hero-squares-2x2" class="size-4" />
            <span>
              {@scope.workspace.name}
              <span class="text-xs text-base-content/50">All projects</span>
            </span>
          </.link>
        </li>
        <li class="menu-title text-xs text-base-content/40 px-2 pt-2">PROJECTS</li>
        <li :for={project <- @projects}>
          <.link navigate={~p"/projects/#{project.id}/sessions"} class={["gap-2 text-sm", Scope.project?(@scope) && @scope.project_id == project.id && "active"]}>
            <.icon name="hero-folder" class="size-4" />
            {project.name}
          </.link>
        </li>
      </ul>
    </details>
    """
  end

  # ---------------------------------------------------------------------------
  # scope_badge/1
  # ---------------------------------------------------------------------------

  @doc """
  Renders a one-line scope subtitle for list page headers.

  Workspace scope: "Across all projects"
  Project scope: "<project name> only"
  """
  attr :scope, Scope, required: true

  def scope_badge(assigns) do
    ~H"""
    <p class="text-xs text-base-content/40 mt-0.5">
      <%= if Scope.workspace?(@scope) do %>
        Across all projects
      <% else %>
        <%= @scope.project && @scope.project.name %> only
      <% end %>
    </p>
    """
  end

  # ---------------------------------------------------------------------------
  # scope_breadcrumb/1
  # ---------------------------------------------------------------------------

  @doc """
  Breadcrumb showing scope root + current page title.

  Project scope: "EITS Web / Sessions"
  Workspace scope: "Personal Workspace / Sessions"
  """
  attr :scope, Scope, required: true
  attr :page_title, :string, required: true

  def scope_breadcrumb(assigns) do
    ~H"""
    <nav class="flex items-center gap-1.5 text-xs text-base-content/50">
      <span class="font-medium text-base-content/70">
        <%= if Scope.project?(@scope), do: @scope.project.name, else: @scope.workspace.name %>
      </span>
      <.icon name="hero-chevron-right" class="size-3" />
      <span>{@page_title}</span>
    </nav>
    """
  end
end
