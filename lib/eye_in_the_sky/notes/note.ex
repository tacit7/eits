defmodule EyeInTheSky.Notes.Note do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "notes" do
    field :uuid, :string
    field :parent_type, :string
    field :parent_id, :string
    field :title, :string
    field :body, :string
    field :starred, :integer, default: 0
    field :created_at, :string
  end

  @doc false
  def changeset(note, attrs) do
    note
    |> cast(attrs, [:uuid, :parent_type, :parent_id, :title, :body, :starred, :created_at])
    |> maybe_generate_uuid()
    |> maybe_set_created_at()
    |> validate_required([:parent_type, :parent_id, :body])
    |> validate_inclusion(:parent_type, ["session", "task", "agent", "project", "system"])
  end

  defp maybe_generate_uuid(changeset) do
    if get_field(changeset, :uuid) do
      changeset
    else
      put_change(changeset, :uuid, Ecto.UUID.generate())
    end
  end

  defp maybe_set_created_at(changeset) do
    if get_field(changeset, :created_at) do
      changeset
    else
      put_change(changeset, :created_at, DateTime.utc_now() |> DateTime.to_iso8601())
    end
  end
end
