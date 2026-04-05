defmodule EyeInTheSky.ScheduledJobs.ScheduledJob do
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
    field :last_run_at, :utc_datetime_usec
    field :next_run_at, :utc_datetime_usec
    field :run_count, :integer, default: 0
    field :created_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
    field :project_id, :integer
    # :id = bigint, matches subagent_prompts PK
    field :prompt_id, :id
    field :timezone, :string, default: "Etc/UTC"

    has_many :runs, EyeInTheSky.ScheduledJobs.JobRun, foreign_key: :job_id

    belongs_to :prompt, EyeInTheSky.Prompts.Prompt,
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
      :prompt_id,
      :timezone
    ])
    |> validate_required([:name, :job_type, :schedule_type, :schedule_value])
    |> validate_inclusion(:job_type, ["spawn_agent", "shell_command", "mix_task", "daily_digest"])
    |> validate_inclusion(:origin, ["system", "user"])
    |> validate_inclusion(:schedule_type, ["interval", "cron"])
    |> validate_job_config()
    |> unique_constraint(:prompt_id, name: :idx_scheduled_jobs_unique_prompt)
  end

  defp validate_job_config(changeset) do
    job_type = get_field(changeset, :job_type)
    config_raw = get_field(changeset, :config) || "{}"

    config =
      case Jason.decode(config_raw) do
        {:ok, map} -> map
        _ -> %{}
      end

    case job_type do
      "shell_command" -> validate_shell_command_config(changeset, config)
      "mix_task" -> validate_mix_task_config(changeset, config)
      "spawn_agent" -> validate_spawn_agent_config(changeset, config)
      "daily_digest" -> validate_daily_digest_config(changeset, config)
      _ -> changeset
    end
  end

  defp validate_shell_command_config(changeset, config) do
    if (config["command"] || "") |> String.trim() == "" do
      add_error(changeset, :config, "command is required for shell jobs")
    else
      changeset
    end
  end

  defp validate_mix_task_config(changeset, config) do
    if (config["task"] || "") |> String.trim() == "" do
      add_error(changeset, :config, "task is required for mix jobs")
    else
      changeset
    end
  end

  defp validate_spawn_agent_config(changeset, _config), do: changeset

  defp validate_daily_digest_config(changeset, _config), do: changeset
end
