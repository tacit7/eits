defmodule EyeInTheSky.Repo.Migrations.ConvertUuidColumnsToNativeUuid do
  use Ecto.Migration

  @doc """
  Converts all varchar(255) UUID columns to native PostgreSQL uuid type.
  The cast `uuid::uuid` is safe — all existing values are valid UUID strings,
  and NULLs remain NULL.
  """
  def up do
    # Each ALTER COLUMN drops the existing index, converts the type, and the
    # index is recreated below. Postgres handles varchar -> uuid cast natively.

    alter table(:agents) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:sessions) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:messages) do
      modify :uuid, :uuid, from: {:string, size: 255}
      modify :source_uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:tasks) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:notes) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:bookmarks) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:teams) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:channels) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:channel_members) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:file_attachments) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:message_reactions) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:notifications) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end

    alter table(:subagent_prompts) do
      modify :uuid, :uuid, from: {:string, size: 255}
    end
  end

  def down do
    alter table(:agents) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:sessions) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:messages) do
      modify :uuid, :string, size: 255, from: :uuid
      modify :source_uuid, :string, size: 255, from: :uuid
    end

    alter table(:tasks) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:notes) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:bookmarks) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:teams) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:channels) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:channel_members) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:file_attachments) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:message_reactions) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:notifications) do
      modify :uuid, :string, size: 255, from: :uuid
    end

    alter table(:subagent_prompts) do
      modify :uuid, :string, size: 255, from: :uuid
    end
  end
end
