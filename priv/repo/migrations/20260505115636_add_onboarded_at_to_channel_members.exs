defmodule EyeInTheSky.Repo.Migrations.AddOnboardedAtToChannelMembers do
  use Ecto.Migration

  def change do
    alter table(:channel_members) do
      add :onboarded_at, :utc_datetime_usec, null: true
    end
  end
end
