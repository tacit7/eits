defmodule EyeInTheSky.Repo.Migrations.AddBuiltinMatcherToIamPolicies do
  use Ecto.Migration

  def change do
    alter table(:iam_policies) do
      add :builtin_matcher, :string
    end

    create index(:iam_policies, [:builtin_matcher], where: "builtin_matcher IS NOT NULL")
  end
end
