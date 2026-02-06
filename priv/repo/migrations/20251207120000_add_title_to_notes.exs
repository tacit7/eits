defmodule EyeInTheSkyWeb.Repo.Migrations.AddTitleToNotes_20251207 do
  use Ecto.Migration

  def change do
    # NOTE: This migration is skipped after schema rework v2
    # The notes table is no longer part of the database schema
    # Notes functionality has been replaced with session notes tracking
    :ok
  end
end
