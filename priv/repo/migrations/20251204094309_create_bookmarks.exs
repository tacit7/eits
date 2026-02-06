defmodule EyeInTheSkyWeb.Repo.Migrations.CreateBookmarks do
  use Ecto.Migration

  def change do
    create table(:bookmarks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # What's being bookmarked
      add :bookmark_type, :string, null: false
      add :bookmark_id, :string

      # File-specific fields
      add :file_path, :text
      add :line_number, :integer

      # URL-specific fields
      add :url, :text

      # Common metadata
      add :title, :string
      add :description, :text

      # Organization
      add :category, :string
      add :priority, :integer, default: 0
      add :position, :integer

      # Context
      add :project_id, :integer
      add :agent_id, :string

      # Timestamps
      add :accessed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Indexes for common queries
    create index(:bookmarks, [:bookmark_type])
    create index(:bookmarks, [:project_id])
    create index(:bookmarks, [:agent_id])
    create index(:bookmarks, [:category])
    create index(:bookmarks, [:priority])
    create index(:bookmarks, [:inserted_at])
  end
end
