defmodule EyeInTheSkyWeb.ScheduledJobs.JobRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "job_runs" do
    field :status, :string
    field :started_at, :string
    field :completed_at, :string
    field :result, :string
    field :session_id, :integer
    field :created_at, :string

    belongs_to :job, EyeInTheSkyWeb.ScheduledJobs.ScheduledJob,
      foreign_key: :job_id,
      type: :integer
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:job_id, :status, :started_at, :completed_at, :result, :session_id, :created_at])
    |> validate_required([:job_id, :status])
    |> validate_inclusion(:status, ["running", "completed", "failed"])
  end
end
