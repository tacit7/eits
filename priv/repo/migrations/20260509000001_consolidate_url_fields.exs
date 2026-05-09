defmodule EyeInTheSky.Repo.Migrations.ConsolidateUrlFields do
  use Ecto.Migration

  def change do
    # Remove duplicate URL fields, keeping only git_remote as the canonical field
    alter table(:projects) do
      remove :remote_url
      remove :repo_url
    end
  end
end
