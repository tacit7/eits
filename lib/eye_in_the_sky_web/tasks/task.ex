defmodule EyeInTheSkyWeb.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "tasks" do
    field :uuid, :string
    field :title, :string
    field :description, :string
    field :priority, :integer, default: 0
    field :due_at, :string
    field :completed_at, :string
    field :archived, :boolean, default: false
    field :agent_id, :integer

    belongs_to :state, EyeInTheSkyWeb.Tasks.WorkflowState, foreign_key: :state_id, type: :integer
    belongs_to :project, EyeInTheSkyWeb.Projects.Project, foreign_key: :project_id, type: :integer

    belongs_to :agent, EyeInTheSkyWeb.Agents.Agent,
      define_field: false,
      foreign_key: :agent_id,
      type: :integer

    many_to_many :agents, EyeInTheSkyWeb.Agents.Agent,
      join_through: "task_sessions",
      join_keys: [task_id: :id, session_id: :id],
      on_replace: :delete

    many_to_many :commits, EyeInTheSkyWeb.Commits.Commit,
      join_through: "commit_tasks",
      join_keys: [task_id: :id, commit_id: :id],
      on_replace: :delete

    many_to_many :tags, EyeInTheSkyWeb.Tasks.Tag,
      join_through: "task_tags",
      join_keys: [task_id: :id, tag_id: :id],
      on_replace: :delete

    field :created_at, :string
    field :updated_at, :string
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :uuid,
      :title,
      :description,
      :state_id,
      :project_id,
      :agent_id,
      :priority,
      :due_at,
      :completed_at,
      :archived,
      :created_at,
      :updated_at
    ])
    |> validate_required([:title])
  end
end
