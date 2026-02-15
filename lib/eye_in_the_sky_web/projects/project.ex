defmodule EyeInTheSkyWeb.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "projects" do
    field :name, :string
    field :path, :string
    field :remote_url, :string

    has_many :agents, EyeInTheSkyWeb.Agents.Agent
    # Note: commits now use session_id as primary key (session-centric model)
    # Use Commits.list_commits_for_session/1 instead
  end

  # Note: created_at and updated_at fields are stored by Go in a format that Ecto can't parse
  # They are omitted from the schema to avoid type casting errors

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :path, :remote_url])
    |> validate_required([:name])
    |> unique_constraint(:path)
  end
end
