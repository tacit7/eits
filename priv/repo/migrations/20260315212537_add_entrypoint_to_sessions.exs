defmodule EyeInTheSky.Repo.Migrations.AddEntrypointToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :entrypoint, :string
    end
  end
end
