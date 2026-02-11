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
    |> cast(attrs, [:uuid, :parent_type, :parent_id, :title, :body])
    |> validate_required([:parent_type, :parent_id, :body])
    |> validate_inclusion(:parent_type, ["session", "task", "agent"])
  end
end
