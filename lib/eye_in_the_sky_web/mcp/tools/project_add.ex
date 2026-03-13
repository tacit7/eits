defmodule EyeInTheSkyWeb.MCP.Tools.ProjectAdd do
  @moduledoc "Create a new project in Eye in the Sky for tracking agents and tasks"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :name, :string, required: true, description: "Project name (required)"
    field :slug, :string, description: "URL-friendly slug"
    field :path, :string, description: "Local filesystem path"
    field :remote_url, :string, description: "Git remote URL (e.g., git@github.com:org/repo.git)"
    field :git_remote, :string, description: "Git remote name (e.g., origin, upstream)"
    field :repo_url, :string, description: "Web URL for browsing the repository (e.g., https://github.com/org/repo)"
    field :branch, :string, description: "Git branch name"
    field :active, :boolean, description: "Active status (default: true)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Projects

    attrs = %{
      name: params[:name],
      slug: params[:slug],
      path: params[:path],
      remote_url: params[:remote_url],
      git_remote: params[:git_remote],
      repo_url: params[:repo_url],
      branch: params[:branch],
      active: if(params[:active] == false, do: false, else: true)
    }

    result =
      case Projects.create_project(attrs) do
        {:ok, project} ->
          %{success: true, message: "Project created", project_id: project.id}

        {:error, cs} ->
          %{success: false, message: "Failed: #{inspect(cs.errors)}"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end
end
