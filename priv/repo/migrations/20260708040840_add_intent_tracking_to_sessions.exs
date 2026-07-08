defmodule EyeInTheSky.Repo.Migrations.AddIntentTrackingToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :turn_start_at, :utc_datetime_usec
      add :intent_set_at, :utc_datetime_usec
    end

    create constraint(:sessions, :sessions_intent_check,
             check: "intent IS NULL OR intent IN ('done')"
           )
  end
end
