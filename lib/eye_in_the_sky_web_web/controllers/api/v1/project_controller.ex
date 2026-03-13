defmodule EyeInTheSkyWebWeb.Api.V1.ProjectController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.Projects

  @doc """
  GET /api/v1/projects - List all projects.
  """
  def index(conn, _params) do
    projects = Projects.list_projects()

    json(conn, %{
      success: true,
      projects:
        Enum.map(projects, fn p ->
          %{id: p.id, name: p.name, path: p.path, slug: p.slug, active: p.active}
        end)
    })
  end

  @doc """
  GET /api/v1/projects/:id - Get a project by ID.
  """
  def show(conn, %{"id" => id}) do
    try do
      project = Projects.get_project!(id)

      json(conn, %{
        success: true,
        project: %{
          id: project.id,
          name: project.name,
          path: project.path,
          slug: project.slug,
          active: project.active
        }
      })
    rescue
      Ecto.NoResultsError ->
        conn |> put_status(:not_found) |> json(%{error: "Project not found"})
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
      active: if(params["active"] == false, do: false, else: true)
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

  defp translate_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
