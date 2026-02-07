defmodule EyeInTheSkyWeb.Notes.Note do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  schema "notes" do
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
    |> cast(attrs, [:id, :parent_type, :parent_id, :title, :body])
    |> maybe_generate_id()
    |> validate_required([:parent_type, :parent_id, :body])
    |> validate_inclusion(:parent_type, ["session", "task", "agent"])
  end

  defp maybe_generate_id(changeset) do
    if get_field(changeset, :id) do
      changeset
    else
      put_change(changeset, :id, Ecto.UUID.generate())
    end
  end
end
