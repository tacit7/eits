defmodule EyeInTheSky.Repo.Migrations.AddFieldsToIamDecisions do
  use Ecto.Migration

  def change do
    alter table(:iam_decisions) do
      add :decision_id, :uuid
      add :project_path, :string
      add :raw_payload, :map
    end

    create index(:iam_decisions, [:decision_id], unique: true, where: "decision_id IS NOT NULL")
  end
end
