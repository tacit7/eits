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
  """
  def get_project_tasks(project_id, opts \\ []) when is_integer(project_id) do
    state_id = Keyword.get(opts, :state_id)
    sort_by = Keyword.get(opts, :sort_by, "created_desc")
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset, 0)

    query =
      from(t in EyeInTheSkyWeb.Tasks.Task,
        where: t.project_id == ^project_id
      )

    query =
      if state_id do
        where(query, [t], t.state_id == ^state_id)
      else
        query
      end

    query =
      case sort_by do
        "created_asc" -> order_by(query, [t], asc: t.created_at)
        "priority" -> order_by(query, [t], desc: t.priority, desc: t.created_at)
        _ -> order_by(query, [t], desc: t.created_at)
      end

    query = if limit, do: limit(query, ^limit), else: query
    query = if offset > 0, do: offset(query, ^offset), else: query

    query
    |> preload([:state, :tags, :agents])
    |> Repo.all()
  end

  def count_project_tasks(project_id, opts \\ []) when is_integer(project_id) do
    state_id = Keyword.get(opts, :state_id)

    query = from(t in EyeInTheSkyWeb.Tasks.Task, where: t.project_id == ^project_id)
    query = if state_id, do: where(query, [t], t.state_id == ^state_id), else: query

    EyeInTheSkyWeb.Repo.aggregate(query, :count, :id)
  end
end
