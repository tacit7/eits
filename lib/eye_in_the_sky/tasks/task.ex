defmodule EyeInTheSky.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "tasks" do
    field :uuid, Ecto.UUID
    field :title, :string
    field :description, :string
    field :priority, :integer, default: 0
    field :position, :integer, default: 0
    field :due_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :archived, :boolean, default: false
    field :agent_id, :integer

    belongs_to :state, EyeInTheSky.Tasks.WorkflowState, foreign_key: :state_id, type: :integer
    belongs_to :project, EyeInTheSky.Projects.Project, foreign_key: :project_id, type: :integer
    belongs_to :team, EyeInTheSky.Teams.Team, foreign_key: :team_id, type: :integer

    # agent_id is declared as a plain field above; define_field: false prevents a
    # duplicate field error. tasks.agent_id is a FK to the agents table (not sessions).
    belongs_to :agent, EyeInTheSky.Agents.Agent,
      define_field: false,
      foreign_key: :agent_id,
      type: :integer

    many_to_many :sessions, EyeInTheSky.Sessions.Session,
      join_through: "task_sessions",
      join_keys: [task_id: :id, session_id: :id],
      on_replace: :delete

    many_to_many :commits, EyeInTheSky.Commits.Commit,
      join_through: "commit_tasks",
      join_keys: [task_id: :id, commit_id: :id],
      on_replace: :delete

    many_to_many :tags, EyeInTheSky.Tasks.Tag,
      join_through: "task_tags",
      join_keys: [task_id: :id, tag_id: :id],
      on_replace: :delete

    has_many :checklist_items, EyeInTheSky.Tasks.ChecklistItem,
      preload_order: [asc: :position, asc: :id]

    field :created_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec

    # Populated by EyeInTheSky.Notes.with_notes_count/1, which batch-loads
    # annotations for a list of tasks. Called from EyeInTheSky.Tasks (tasks.ex)
    # and EyeInTheSky.ProjectLive.Kanban (kanban.ex) after querying tasks.
    field :notes_count, :integer, virtual: true, default: 0
    field :notes, :any, virtual: true, default: []
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
      :team_id,
      :agent_id,
      :priority,
      :position,
      :due_at,
      :completed_at,
      :archived,
      :created_at,
      :updated_at
    ])
    |> then(fn cs ->
      if get_field(cs, :uuid), do: cs, else: put_change(cs, :uuid, Ecto.UUID.generate())
    end)
    |> validate_required([:title])
    |> validate_inclusion(:state_id, [1, 2, 3, 4], message: "must be a valid workflow state")
    |> validate_number(:project_id, greater_than: 0)
    |> foreign_key_constraint(:team_id)
  end
end
