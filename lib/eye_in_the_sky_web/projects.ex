defmodule EyeInTheSkyWeb.Projects do
  @moduledoc """
  The Projects context for managing projects.
  """

  use EyeInTheSkyWeb.CrudHelpers, schema: EyeInTheSkyWeb.Projects.Project

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
  def get_project!(id), do: get!(id)

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
  def create_project(attrs \\ %{}), do: create(attrs)

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs), do: __MODULE__.update(project, attrs)

  @doc """
  Deletes a project.
  """
  def delete_project(%Project{} = project), do: delete(project)

  @doc """
  Gets tasks for a project.
  """
  def get_project_tasks(project_id, opts \\ []) when is_integer(project_id) do
    sort_by = Keyword.get(opts, :sort_by, "created_desc")

    order =
      case sort_by do
        "created_asc" -> [asc: :created_at]
        "priority" -> [desc: :priority, asc: :position]
        _ -> [asc: :position, desc: :created_at]
      end

    base_project_tasks_query(project_id, opts)
    |> order_by(^order)
    |> QueryBuilder.maybe_limit(opts)
    |> QueryBuilder.maybe_offset(opts)
    |> preload([:state, :tags, :sessions, :checklist_items])
    |> Repo.all()
  end

  def count_project_tasks(project_id, opts \\ []) when is_integer(project_id) do
    base_project_tasks_query(project_id, opts)
    |> EyeInTheSkyWeb.Repo.aggregate(:count, :id)
  end

  defp base_project_tasks_query(project_id, opts) do
    include_archived = Keyword.get(opts, :include_archived, false)

    query = from(t in EyeInTheSkyWeb.Tasks.Task, where: t.project_id == ^project_id)
    query = if include_archived, do: query, else: where(query, [t], t.archived == false)
    QueryBuilder.maybe_where(query, opts, :state_id)
  end
end
