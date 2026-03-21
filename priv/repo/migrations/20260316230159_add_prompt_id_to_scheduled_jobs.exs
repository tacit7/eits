defmodule EyeInTheSky.Repo.Migrations.AddPromptIdToScheduledJobs do
  use Ecto.Migration

  def up do
    alter table(:scheduled_jobs) do
      add :prompt_id, references(:subagent_prompts, on_delete: :restrict), null: true
    end

    create index(:scheduled_jobs, [:prompt_id])

    create unique_index(:scheduled_jobs, [:prompt_id],
             where: "prompt_id IS NOT NULL",
             name: :idx_scheduled_jobs_unique_prompt
           )
  end

  def down do
    drop_if_exists index(:scheduled_jobs, [:prompt_id])

    drop_if_exists unique_index(:scheduled_jobs, [:prompt_id],
                     name: :idx_scheduled_jobs_unique_prompt
                   )

    alter table(:scheduled_jobs) do
      remove :prompt_id
    end
  end
end
