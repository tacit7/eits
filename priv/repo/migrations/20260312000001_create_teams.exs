defmodule EyeInTheSky.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    # ── Teams ─────────────────────────────────────────────────
    create table(:teams) do
      add :uuid, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :status, :string, default: "active"
      add :project_id, references(:projects, on_delete: :nilify_all)
      add :created_at, :utc_datetime
      add :archived_at, :utc_datetime
    end

    create unique_index(:teams, [:uuid])
    create unique_index(:teams, [:name])
    create index(:teams, [:project_id])
    create index(:teams, [:status])

    # ── Team Members ──────────────────────────────────────────
    create table(:team_members) do
      add :team_id, references(:teams, on_delete: :delete_all), null: false
      add :agent_id, references(:agents, on_delete: :delete_all)
      add :session_id, references(:sessions, on_delete: :nilify_all)
      add :name, :string, null: false
      add :role, :string, default: "member"
      add :status, :string, default: "idle"
      add :joined_at, :utc_datetime
      add :last_activity_at, :utc_datetime
    end

    create unique_index(:team_members, [:team_id, :name])
    create index(:team_members, [:team_id])
    create index(:team_members, [:agent_id])
    create index(:team_members, [:session_id])

    # ── Add team_id to tasks ───────────────────────────────────
    alter table(:tasks) do
      add :team_id, references(:teams, on_delete: :nilify_all)
    end

    create index(:tasks, [:team_id])
  end
end
