defmodule EyeInTheSkyWeb.Api.V1.ProjectController do
  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.Projects
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/projects - List all projects.
  """
  def index(conn, params) do
    projects =
      if path = params["path"] do
        case Projects.get_project_by_path(path) do
          {:ok, project} -> [project]
          {:error, :not_found} -> []
        end
      else
        Projects.list_projects()
      end

    json(conn, %{
      success: true,
      projects: Enum.map(projects, &ApiPresenter.present_project/1)
    })
  end

  @doc """
  GET /api/v1/projects/:id - Get a project by ID.
  """
  def show(conn, %{"id" => id}) do
    case Projects.get_project(id) do
      {:error, :not_found} ->
        {:error, :not_found, "Project not found"}

      {:ok, project} ->
        json(conn, %{success: true, project: ApiPresenter.present_project(project)})
    end
  end

  @doc """
  POST /api/v1/projects - Create a new project.

  Parameters:
    - name (required): Project name
    - slug: URL-friendly project identifier
    - path: File system path to the project
    - git_remote: Git remote URL (e.g., git@github.com:user/repo.git or https://github.com/user/repo)
    - branch: Default git branch
    - active: Whether project is active (default: true)
  """
  def create(conn, params) do
    attrs = %{
      name: params["name"],
      slug: params["slug"],
      path: params["path"],
      git_remote: params["git_remote"],
      branch: params["branch"],
      active: Map.get(params, "active", true)
    }

    case Projects.create_project(attrs) do
      {:ok, project} ->
        conn
        |> put_status(:created)
        |> json(%{success: true, message: "Project created", project_id: project.id})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create project", details: translate_errors(changeset)})
    end
  end
end
