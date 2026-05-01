defmodule EyeInTheSky.Repo.Migrations.AddPartialIndexSessionsZombieSweep do
  use Ecto.Migration

  def change do
    create index(:sessions, [:last_activity_at],
             where: "status = 'working'",
             name: :sessions_last_activity_at_working_idx
           )

    create index(:sessions, [:started_at],
             where: "status = 'working' AND last_activity_at IS NULL",
             name: :sessions_started_at_working_no_activity_idx
           )
  end
end
