defmodule EyeInTheSky.Repo.Migrations.CreateIamPoliciesAndDecisions do
  use Ecto.Migration

  def change do
    create table(:iam_policies) do
      add :system_key, :string
      add :name, :string, null: false
      add :effect, :string, null: false
      add :agent_type, :string, null: false, default: "*"
      add :project_id, references(:projects, on_delete: :delete_all)
      add :project_path, :string, default: "*"
      add :action, :string, null: false, default: "*"
      add :resource_glob, :string
      add :condition, :map, default: %{}
      add :priority, :integer, null: false, default: 0
      add :enabled, :boolean, null: false, default: true
      add :message, :string
      add :editable_fields, {:array, :string}, default: []

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:iam_policies, [:system_key],
             where: "system_key IS NOT NULL",
             name: :iam_policies_system_key_unique_index
           )

    create index(:iam_policies, [:agent_type, :action, :enabled])
    create index(:iam_policies, [:project_id])

    create table(:iam_decisions) do
      add :session_uuid, :uuid
      add :event, :string
      add :agent_type, :string
      add :project_id, references(:projects, on_delete: :nilify_all)
      add :tool, :string
      add :resource_path, :string
      add :permission, :string
      add :winning_policy_id, references(:iam_policies, on_delete: :nilify_all)
      add :winning_policy_system_key, :string
      add :winning_policy_name, :string
      add :default, :boolean, default: false
      add :reason, :text
      add :instructions_snapshot, {:array, :map}, default: []
      add :evaluated_count, :integer
      add :duration_us, :integer
      add :cache_hit, :boolean

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:iam_decisions, [:session_uuid])
    create index(:iam_decisions, [:permission, :inserted_at])
  end
end
