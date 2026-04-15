defmodule EyeInTheSky.Projects do
  @moduledoc """
  The Projects context for managing projects.
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Projects.Project

  require Logger

  import Ecto.Query, warn: false
  alias EyeInTheSky.Projects.Project
  alias EyeInTheSky.Repo

  @doc """
  Returns the list of projects.
  """
  def list_projects do
    Project
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  @doc """
  Returns active projects ordered for sidebar display:
  bookmarked first, then case-insensitive name, then id for stability.
  """
  def list_projects_for_sidebar do
    Project
    |> where([p], p.active == true)
    |> order_by([p],
      asc: not p.bookmarked,
      asc: fragment("lower(?)", p.name),
      asc: p.id
    )
    |> Repo.all()
  end

  @doc """
  Gets a single project.

  Raises `Ecto.NoResultsError` if the Project does not exist.
  """
  def get_project!(id), do: get!(id)

  @doc """
  Gets a single project by id. Returns {:ok, project} | {:error, :not_found}.
  """
  def get_project(id) do
    case Repo.get(Project, id) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  @doc """
  Gets a project with agents preloaded. Raises if not found.
  """
  def get_project_with_agents!(id) do
    get_project!(id) |> Repo.preload([:agents])
  end

  @doc """
  Gets a single project by name. Returns {:ok, project} | {:error, :not_found}.
  """
  def get_project_by_name(name) do
    case Repo.get_by(Project, name: name) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  @doc """
  Gets a single project by path. Returns {:ok, project} | {:error, :not_found}.
  """
  def get_project_by_path(path) do
    case Repo.get_by(Project, path: path) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
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
  Sets the bookmarked state of a project. Returns {:ok, project} or {:error, :not_found}.
  """
  def set_bookmarked(project_id, bookmarked) when is_boolean(bookmarked) do
    case get_project(project_id) do
      {:error, :not_found} ->
        {:error, :not_found}

      {:ok, project} ->
        project
        |> Project.changeset(%{bookmarked: bookmarked})
        |> Repo.update()
    end
  end

  @doc """
  Resolves a project from request params.

  Looks up by `"project_id"`, `"project_path"` (creating if not found), or `"project_name"` —
  in that order. Returns `{:ok, id, name}`, `{:ok, nil, nil}`, or `{:error, code, message}`.
  """
  @spec resolve_project(map()) ::
          {:ok, integer() | nil, String.t() | nil} | {:error, String.t(), String.t()}
  def resolve_project(params) do
    project_id = parse_project_id(params["project_id"])
    project_path = params["project_path"]
    project_name = params["project_name"]

    cond do
      project_id != nil ->
        case get_project(project_id) do
          {:error, :not_found} ->
            {:error, "project_not_found", "project_id #{project_id} does not exist"}

          {:ok, project} ->
            {:ok, project.id, project.name}
        end

      project_path not in [nil, ""] ->
        resolve_project_by_path(project_path)

      project_name not in [nil, ""] ->
        case get_project_by_name(project_name) do
          {:error, :not_found} -> {:ok, nil, nil}
          {:ok, project} -> {:ok, project.id, project.name}
        end

      true ->
        {:ok, nil, nil}
    end
  end

  defp resolve_project_by_path(path) do
    case get_project_by_path(path) do
      {:error, :not_found} -> create_or_retry_project(path)
      {:ok, project} -> {:ok, project.id, project.name}
    end
  end

  defp create_or_retry_project(path) do
    name = Path.basename(path)

    case create_project(%{name: name, path: path, active: true}) do
      {:ok, project} ->
        Logger.info("resolve_project: created project id=#{project.id} for path=#{path}")
        {:ok, project.id, project.name}

      {:error, _changeset} ->
        # Race condition: try lookup again
        case get_project_by_path(path) do
          {:error, :not_found} ->
            {:error, "project_creation_failed", "failed to create project for path: #{path}"}

          {:ok, project} ->
            {:ok, project.id, project.name}
        end
    end
  end

  defdelegate parse_project_id(id), to: EyeInTheSky.Utils.ToolHelpers, as: :parse_int

  @doc "Preloads associations onto a project struct."
  def preload_project(%Project{} = project, assocs) do
    Repo.preload(project, assocs)
  end
end
