defmodule EyeInTheSky.Repo.Migrations.AddEventToIamPolicies do
  use Ecto.Migration

  def change do
    alter table(:iam_policies) do
      add :event, :string, default: "PreToolUse", null: false
    end

    create index(:iam_policies, [:event])
  end
end
