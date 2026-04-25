defmodule EyeInTheSky.Scope do
  @moduledoc """
  First-class scope object that carries user + workspace + (optionally) project context.

  Two scope types:

  - `:workspace` — aggregate view across all projects in a workspace.
    Used by /workspace/* routes. Queries join through projects to workspace.

  - `:project` — view/actions for a single project.
    Used by /projects/:project_id/* routes. Queries filter directly by project_id.

  ## Rules

  - Agent sessions always belong to a project. Never create workspace-owned sessions.
  - Use `Scope.workspace?/1` and `Scope.project?/1` for dispatch instead of scattering
    `if project_id` checks throughout LiveViews and context modules.
  - The URL and the assigned `@scope` are the source of truth — do not derive scope from
    cookies, session, or assigns.

  ## Usage

      # In a LiveView mount/3:
      scope = Scope.for_project(current_user, workspace, project)
      {:ok, assign(socket, scope: scope)}

      # In a context:
      def list_sessions(%Scope{type: :project, project_id: pid}, opts) do ...
      def list_sessions(%Scope{type: :workspace, workspace_id: wid}, opts) do ...
  """

  @enforce_keys [:type, :user_id, :workspace_id]

  defstruct [
    :type,
    :user_id,
    :workspace_id,
    :workspace,
    :project_id,
    :project
  ]

  @type t :: %__MODULE__{
          type: :workspace | :project,
          user_id: integer(),
          workspace_id: integer(),
          workspace: struct() | nil,
          project_id: integer() | nil,
          project: struct() | nil
        }

  @doc "Build a workspace-level scope."
  def for_workspace(user, workspace) do
    %__MODULE__{
      type: :workspace,
      user_id: user.id,
      workspace_id: workspace.id,
      workspace: workspace
    }
  end

  @doc "Build a project-level scope."
  def for_project(user, workspace, project) do
    %__MODULE__{
      type: :project,
      user_id: user.id,
      workspace_id: workspace.id,
      workspace: workspace,
      project_id: project.id,
      project: project
    }
  end

  @doc "True when scope covers all projects in a workspace."
  def workspace?(%__MODULE__{type: :workspace}), do: true
  def workspace?(_), do: false

  @doc "True when scope is limited to a single project."
  def project?(%__MODULE__{type: :project}), do: true
  def project?(_), do: false
end
