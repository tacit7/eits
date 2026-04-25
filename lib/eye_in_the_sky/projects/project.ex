defmodule EyeInTheSky.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "projects" do
    field :name, :string
    field :slug, :string
    field :path, :string
    field :remote_url, :string
    field :git_remote, :string
    field :repo_url, :string
    field :branch, :string
    field :active, :boolean, default: true
    field :bookmarked, :boolean, default: false

    belongs_to :workspace, EyeInTheSky.Workspaces.Workspace

    has_many :agents, EyeInTheSky.Agents.Agent
    has_many :sessions, EyeInTheSky.Sessions.Session
    # Note: commits now use session_id as primary key (session-centric model)
    # Use Commits.list_commits_for_session/1 instead
  end

  # Note: created_at and updated_at fields are stored by Go in a format that Ecto can't parse
  # They are omitted from the schema to avoid type casting errors

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name,
      :slug,
      :path,
      :remote_url,
      :git_remote,
      :repo_url,
      :branch,
      :active,
      :bookmarked,
      :workspace_id
    ])
    |> validate_required([:name])
    |> unique_constraint(:path)
  end
end
