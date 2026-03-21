defmodule EyeInTheSky.Commits.Commit do
  use Ecto.Schema
  import Ecto.Changeset

  schema "commits" do
    field :session_id, :integer
    field :commit_hash, :string
    field :commit_message, :string

    belongs_to :session, EyeInTheSky.Sessions.Session,
      define_field: false,
      foreign_key: :session_id,
      type: :integer

    many_to_many :tasks, EyeInTheSky.Tasks.Task,
      join_through: "commit_tasks",
      join_keys: [commit_id: :id, task_id: :id]

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
  end

  @doc false
  def changeset(commit, attrs) do
    commit
    |> cast(attrs, [:session_id, :commit_hash, :commit_message])
    |> validate_required([:session_id, :commit_hash])
  end
end
