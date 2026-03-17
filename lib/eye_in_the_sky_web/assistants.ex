defmodule EyeInTheSkyWeb.Assistants do
  @moduledoc """
  Context for managing reusable assistant definitions.
  An assistant wraps a prompt with executable configuration (model, effort, tool policy, scope).
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Assistants.Assistant

  @doc """
  Returns all assistants, optionally filtered by project.
  """
  def list_assistants(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    include_inactive = Keyword.get(opts, :include_inactive, false)

    query = from(a in Assistant)

    query =
      unless include_inactive do
        where(query, [a], a.active == true)
      else
        query
      end

    query =
      case project_id do
        nil -> query
        id -> where(query, [a], a.project_id == ^id or is_nil(a.project_id))
      end

    query
    |> order_by([a], desc: a.updated_at)
    |> preload([:prompt, :project])
    |> Repo.all()
  end

  @doc """
  Gets a single assistant by ID. Raises if not found.
  """
  def get_assistant!(id) do
    Assistant
    |> Repo.get!(id)
    |> Repo.preload([:prompt, :project])
  end

  @doc """
  Gets a single assistant by ID. Returns nil if not found.
  """
  def get_assistant(id) do
    Assistant
    |> Repo.get(id)
    |> case do
      nil -> nil
      a -> Repo.preload(a, [:prompt, :project])
    end
  end

  @doc """
  Creates an assistant.
  """
  def create_assistant(attrs \\ %{}) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %Assistant{}
    |> Assistant.changeset(attrs)
    |> Ecto.Changeset.put_change(:inserted_at, now)
    |> Ecto.Changeset.put_change(:updated_at, now)
    |> Repo.insert()
  end

  @doc """
  Updates an assistant.
  """
  def update_assistant(%Assistant{} = assistant, attrs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    assistant
    |> Assistant.changeset(attrs)
    |> Ecto.Changeset.put_change(:updated_at, now)
    |> Repo.update()
  end

  @doc """
  Deactivates an assistant (soft delete).
  """
  def deactivate_assistant(%Assistant{} = assistant) do
    update_assistant(assistant, %{active: false})
  end

  @doc """
  Hard deletes an assistant.
  """
  def delete_assistant(%Assistant{} = assistant) do
    Repo.delete(assistant)
  end

  @doc """
  Returns a changeset for tracking assistant changes.
  """
  def change_assistant(%Assistant{} = assistant, attrs \\ %{}) do
    Assistant.changeset(assistant, attrs)
  end

  @doc """
  Lists project-scoped assistants.
  """
  def list_project_assistants(project_id) do
    Assistant
    |> where([a], a.project_id == ^project_id and a.active == true)
    |> order_by([a], desc: a.updated_at)
    |> preload([:prompt])
    |> Repo.all()
  end

  @doc """
  Lists global assistants (no project scope).
  """
  def list_global_assistants do
    Assistant
    |> where([a], is_nil(a.project_id) and a.active == true)
    |> order_by([a], desc: a.updated_at)
    |> preload([:prompt])
    |> Repo.all()
  end
end
