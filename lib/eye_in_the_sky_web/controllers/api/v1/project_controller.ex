defmodule EyeInTheSkyWeb.Api.V1.ProjectController do
  use EyeInTheSkyWeb, :controller

  import EyeInTheSkyWeb.ControllerHelpers

  alias EyeInTheSky.Projects
  alias EyeInTheSkyWeb.Presenters.ApiPresenter

  @doc """
  GET /api/v1/projects - List all projects.
  """
  def index(conn, _params) do
    projects = Projects.list_projects()

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
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})

      project ->
        json(conn, %{success: true, project: ApiPresenter.present_project(project)})
    end
  end

  @doc """
  POST /api/v1/projects - Create a new project.
  """
  def create(conn, params) do
    attrs = %{
      name: params["name"],
      slug: params["slug"],
      path: params["path"],
      remote_url: params["remote_url"],
      git_remote: params["git_remote"],
      repo_url: params["repo_url"],
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
