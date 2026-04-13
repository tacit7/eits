defmodule EyeInTheSky.Repo.Migrations.CreatePushSubscriptions do
  use Ecto.Migration

  def change do
    create table(:push_subscriptions) do
      add :endpoint, :text, null: false
      add :auth, :text, null: false
      add :p256dh, :text, null: false

      timestamps()
    end

    create unique_index(:push_subscriptions, [:endpoint])
  end
end
