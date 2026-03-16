defmodule EyeInTheSkyWeb.ScheduledJobs.ScheduledJob do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "scheduled_jobs" do
    field :name, :string
    field :description, :string
    field :job_type, :string
    field :origin, :string, default: "user"
    field :schedule_type, :string
    field :schedule_value, :string
    field :config, :string, default: "{}"
    field :enabled, :integer, default: 1
    field :last_run_at, :string
    field :next_run_at, :string
    field :run_count, :integer, default: 0
    field :created_at, :string
    field :updated_at, :string
    field :project_id, :integer
    field :prompt_id, :id  # :id = bigint, matches subagent_prompts PK

    has_many :runs, EyeInTheSkyWeb.ScheduledJobs.JobRun, foreign_key: :job_id
    belongs_to :prompt, EyeInTheSkyWeb.Prompts.Prompt,
      foreign_key: :prompt_id,
      references: :id,
      define_field: false
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :name,
      :description,
      :job_type,
      :origin,
      :schedule_type,
      :schedule_value,
      :config,
      :enabled,
      :last_run_at,
      :next_run_at,
      :run_count,
      :created_at,
      :updated_at,
      :project_id,
      :prompt_id
    ])
    |> validate_required([:name, :job_type, :schedule_type, :schedule_value])
    |> validate_inclusion(:job_type, ["spawn_agent", "shell_command", "mix_task", "daily_digest"])
    |> validate_inclusion(:origin, ["system", "user"])
    |> validate_inclusion(:schedule_type, ["interval", "cron"])
    |> unique_constraint(:prompt_id, name: :idx_scheduled_jobs_unique_prompt)
  end
end
