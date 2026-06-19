defmodule EyeInTheSky.Repo.Migrations.CreateIamPolicyDocuments do
  use Ecto.Migration

  def change do
    create table(:iam_policy_documents) do
      add :name, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:iam_policy_documents, ["lower(name)"],
             name: :iam_policy_documents_name_ci_unique
           )

    create table(:iam_document_policies) do
      add :document_id,
          references(:iam_policy_documents, on_delete: :delete_all),
          null: false

      add :policy_id,
          references(:iam_policies, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:iam_document_policies, [:document_id, :policy_id],
             name: :iam_document_policies_unique
           )

    create index(:iam_document_policies, [:policy_id],
             name: :iam_document_policies_policy_id
           )

    create table(:iam_agent_type_documents) do
      add :agent_type, :string, size: 255, null: false

      add :document_id,
          references(:iam_policy_documents, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:iam_agent_type_documents, [:agent_type, :document_id],
             name: :iam_agent_type_documents_unique
           )
  end
end
