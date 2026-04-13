defmodule EyeInTheSky.Repo.Migrations.ConvertNotesStarredToBoolean do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE notes ALTER COLUMN starred DROP DEFAULT")
    execute("ALTER TABLE notes ALTER COLUMN starred TYPE boolean USING (starred = 1)")
    execute("ALTER TABLE notes ALTER COLUMN starred SET DEFAULT false")
  end

  def down do
    execute("ALTER TABLE notes ALTER COLUMN starred DROP DEFAULT")
    execute("ALTER TABLE notes ALTER COLUMN starred TYPE integer USING (CASE WHEN starred THEN 1 ELSE 0 END)")
    execute("ALTER TABLE notes ALTER COLUMN starred SET DEFAULT 0")
  end
end
