defmodule EyeInTheSky.Repo.Migrations.AddStatusMessageToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :status_message, :text
    end
  end
end
