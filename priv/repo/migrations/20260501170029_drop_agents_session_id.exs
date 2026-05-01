defmodule EyeInTheSky.Repo.Migrations.DropAgentsSessionId do
  use Ecto.Migration

  def change do
    # L4: agents.session_id is a legacy integer field with no FK constraint,
    # no index, and zero code readers. It was never exposed via the changeset.
    # Removing it cleans up unused data and eliminates a confusing field that
    # misleads readers into thinking an agent has a 1:1 session relationship
    # (agents have has_many :sessions).
    alter table(:agents) do
      remove :session_id, :integer
    end
  end
end
