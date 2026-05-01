defmodule EyeInTheSky.Repo.Migrations.AddTokenCostCacheToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :total_tokens, :integer, default: 0, null: false
      add :total_cost_usd, :float, default: 0.0, null: false
    end
  end
end
