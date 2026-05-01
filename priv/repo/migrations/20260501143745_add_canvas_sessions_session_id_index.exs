defmodule EyeInTheSky.Repo.Migrations.AddCanvasSessionsSessionIdIndex do
  use Ecto.Migration

  # M-6: canvas_sessions.session_id has no standalone index.
  # The unique (canvas_id, session_id) index exists but cascaded deletes on
  # session_id alone may not use it efficiently — standalone index makes it explicit.

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists index(:canvas_sessions, [:session_id],
                            name: :canvas_sessions_session_id_idx,
                            concurrently: true
                          )
  end

  def down do
    drop_if_exists index(:canvas_sessions, [:session_id], name: :canvas_sessions_session_id_idx)
  end
end
