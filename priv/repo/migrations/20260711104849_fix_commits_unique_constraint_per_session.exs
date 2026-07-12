defmodule EyeInTheSky.Repo.Migrations.FixCommitsUniqueConstraintPerSession do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:commits, [:commit_hash], name: :commits_commit_hash_index)
    create unique_index(:commits, [:session_id, :commit_hash], name: :commits_session_id_commit_hash_index)
  end

  def down do
    drop_if_exists unique_index(:commits, [:session_id, :commit_hash], name: :commits_session_id_commit_hash_index)
    create unique_index(:commits, [:commit_hash], name: :commits_commit_hash_index)
  end
end
