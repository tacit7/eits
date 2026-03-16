defmodule EyeInTheSkyWeb.Repo.Migrations.ChangeSessionsIntentToText do
  use Ecto.Migration

  def up do
    alter table(:sessions) do
      modify :intent, :text
    end
  end

  def down do
    alter table(:sessions) do
      modify :intent, :string
    end
  end
end
