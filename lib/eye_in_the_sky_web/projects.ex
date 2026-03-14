defmodule EyeInTheSkyWeb.Projects do
  @moduledoc """
  The Projects context for managing projects.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Projects.Project
  alias EyeInTheSkyWeb.QueryBuilder

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
  Gets a single project by id. Returns nil if not found.
  """
  def get_project(id), do: Repo.get(Project, id)

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
  """
  def get_project_tasks(project_id, opts \\ []) when is_integer(project_id) do
    sort_by = Keyword.get(opts, :sort_by, "created_desc")

    order =
      case sort_by do
        "created_asc" -> [asc: :created_at]
        "priority" -> [desc: :priority, desc: :created_at]
        _ -> [desc: :created_at]
      end

    base_project_tasks_query(project_id, opts)
    |> order_by(^order)
    |> QueryBuilder.maybe_limit(opts)
    |> QueryBuilder.maybe_offset(opts)
    |> preload([:state, :tags, :agents])
    |> Repo.all()
  end

  def count_project_tasks(project_id, opts \\ []) when is_integer(project_id) do
    base_project_tasks_query(project_id, opts)
    |> EyeInTheSkyWeb.Repo.aggregate(:count, :id)
  end

  defp base_project_tasks_query(project_id, opts) do
    from(t in EyeInTheSkyWeb.Tasks.Task, where: t.project_id == ^project_id)
    |> QueryBuilder.maybe_where(opts, :state_id)
  end
end
