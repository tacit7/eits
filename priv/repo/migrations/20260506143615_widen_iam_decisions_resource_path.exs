defmodule EyeInTheSky.Repo.Migrations.WidenIamDecisionsResourcePath do
  use Ecto.Migration

  def up do
    alter table(:iam_decisions) do
      modify :resource_path, :text
    end
  end

  def down do
    alter table(:iam_decisions) do
      modify :resource_path, :string
    end
  end
end
