defmodule EyeInTheSky.Workspaces do
  @moduledoc """
  Context for workspace management.

  A workspace groups projects under a user. Each user has one default workspace
  for the MVP. The schema supports multiple workspaces per user for future use.
  """

  import Ecto.Query, warn: false

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Workspaces.Workspace

  @doc """
  Returns all workspaces owned by a user.
  """
  def list_workspaces_for_user(user) do
    Workspace
    |> where([w], w.owner_user_id == ^user.id)
    |> order_by([w], asc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the default workspace for a user. Raises if not found.
  """
  def default_workspace_for_user!(user) do
    Repo.get_by!(Workspace, owner_user_id: user.id, default: true)
  end

  @doc """
  Returns the default workspace for a user, or nil if not found.
  """
  def default_workspace_for_user(user) do
    Repo.get_by(Workspace, owner_user_id: user.id, default: true)
  end

  @doc """
  Gets a workspace by id. Returns nil if not found.
  """
  def get_workspace(id), do: Repo.get(Workspace, id)

  @doc """
  Gets a workspace by id. Raises if not found.
  """
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  @doc """
  Creates a workspace.
  """
  def create_workspace(attrs \\ %{}) do
    %Workspace{}
    |> Workspace.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a default workspace for a user. Used during user provisioning.
  """
  def create_default_workspace_for_user(user) do
    create_workspace(%{
      name: "Personal Workspace",
      owner_user_id: user.id,
      default: true
    })
  end
end
