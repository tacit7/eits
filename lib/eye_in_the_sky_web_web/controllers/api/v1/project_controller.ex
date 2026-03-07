defmodule EyeInTheSkyWebWeb.Api.V1.ProjectController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.Projects

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
