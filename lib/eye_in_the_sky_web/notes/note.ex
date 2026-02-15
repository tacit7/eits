defmodule EyeInTheSkyWeb.Notes.Note do
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
    |> cast(attrs, [:uuid, :parent_type, :parent_id, :title, :body, :starred])
    |> maybe_generate_uuid()
    |> validate_required([:parent_type, :parent_id, :body])
    |> validate_inclusion(:parent_type, ["session", "task", "agent"])
  end

  defp maybe_generate_uuid(changeset) do
    if get_field(changeset, :uuid) do
      changeset
    else
      put_change(changeset, :uuid, Ecto.UUID.generate())
    end
  end
end
