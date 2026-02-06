defmodule EyeInTheSkyWeb.Projects do
  @moduledoc """
  The Projects context for managing projects.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Projects.Project

  @doc """
  Returns the list of projects.
  """
  def list_projects do
    Project
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Gets a single project.

  Raises `Ecto.NoResultsError` if the Project does not exist.
  """
  def get_project!(id) do
    Repo.get!(Project, id)
  end

  @doc """
  Gets a single project by name.
  """
  def get_project_by_name(name) do
    Repo.get_by(Project, name: name)
  end

  @doc """
  Creates a project.
  """
  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a project.
  """
  def delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Gets tasks for a project.
  Handles type mismatch: projects.id is INTEGER, tasks.project_id is TEXT.
  """
  def get_project_tasks(project_id) when is_integer(project_id) do
    project_id_str = Integer.to_string(project_id)

    from(t in EyeInTheSkyWeb.Tasks.Task,
      where: t.project_id == ^project_id_str
    )
    |> preload([:state, :tags])
    |> Repo.all()
  end
end
