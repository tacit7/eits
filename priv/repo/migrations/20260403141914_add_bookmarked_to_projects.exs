defmodule EyeInTheSky.Repo.Migrations.AddBookmarkedToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :bookmarked, :boolean, default: false, null: false
    end
  end
end
