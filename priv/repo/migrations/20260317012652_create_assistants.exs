defmodule EyeInTheSkyWeb.Repo.Migrations.CreateAssistants do
  use Ecto.Migration

  def change do
    create table(:assistants) do
      add :name, :string, null: false
      add :prompt_id, references(:subagent_prompts, on_delete: :nilify_all)
      add :model, :string
      add :reasoning_effort, :string
      add :tool_policy, :map, default: %{}
      add :default_trigger_type, :string, default: "manual"
      add :project_id, references(:projects, on_delete: :nilify_all)
      add :team_id, :integer
      add :active, :boolean, default: true, null: false
      add :inserted_at, :naive_datetime
      add :updated_at, :naive_datetime
    end

    create index(:assistants, [:project_id])
    create index(:assistants, [:prompt_id])
    create index(:assistants, [:active])
  end
end
