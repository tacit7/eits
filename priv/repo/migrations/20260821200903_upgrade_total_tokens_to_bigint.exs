defmodule EyeInTheSky.Repo.Migrations.UpgradeTotalTokensToBigint do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      modify :total_tokens, :bigint, default: 0, null: false
    end
  end
end
