defmodule EyeInTheSky.Projects do
  @moduledoc """
  The Projects context for managing projects.
  """

  use EyeInTheSky.CrudHelpers, schema: EyeInTheSky.Projects.Project

  require Logger

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Projects.Project
  alias EyeInTheSky.QueryBuilder

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
  Gets a project with agents preloaded. Raises if not found.
  """
  def get_project_with_agents!(id) do
    get_project!(id) |> Repo.preload([:agents])
  end

  @doc """
  Gets a single project by name.
  """
  def get_project_by_name(name) do
    Repo.get_by(Project, name: name)
  end

  @doc """
  Gets a single project by path.
  """
  def get_project_by_path(path) do
    Repo.get_by(Project, path: path)
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
          nil -> {:error, "project_not_found", "project_id #{project_id} does not exist"}
          project -> {:ok, project.id, project.name}
        end

      project_path not in [nil, ""] ->
        resolve_project_by_path(project_path)

      project_name not in [nil, ""] ->
        case get_project_by_name(project_name) do
          nil -> {:ok, nil, nil}
          project -> {:ok, project.id, project.name}
        end

      true ->
        {:ok, nil, nil}
    end
  end

  defp resolve_project_by_path(path) do
    case get_project_by_path(path) do
      nil ->
        name = Path.basename(path)

        case create_project(%{name: name, path: path, active: true}) do
          {:ok, project} ->
            Logger.info("resolve_project: created project id=#{project.id} for path=#{path}")
            {:ok, project.id, project.name}

          {:error, _changeset} ->
            # Race condition: try lookup again
            case get_project_by_path(path) do
              nil ->
                {:error, "project_creation_failed",
                 "failed to create project for path: #{path}"}

              project ->
                {:ok, project.id, project.name}
            end
        end

      project ->
        {:ok, project.id, project.name}
    end
  end

  defp parse_project_id(nil), do: nil
  defp parse_project_id(id) when is_integer(id), do: id

  defp parse_project_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

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
    |> EyeInTheSky.Repo.aggregate(:count, :id)
  end

  defp base_project_tasks_query(project_id, opts) do
    include_archived = Keyword.get(opts, :include_archived, false)

    query = from(t in EyeInTheSky.Tasks.Task, where: t.project_id == ^project_id)
    query = if include_archived, do: query, else: where(query, [t], t.archived == false)
    QueryBuilder.maybe_where(query, opts, :state_id)
  end
end
