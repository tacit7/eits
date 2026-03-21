defmodule EyeInTheSky.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notifications" do
    field :uuid, :string
    field :title, :string
    field :body, :string
    field :category, :string, default: "system"
    field :read, :boolean, default: false
    field :resource_type, :string
    field :resource_id, :string

    timestamps()
  end

  @categories ~w(agent job system)

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:uuid, :title, :body, :category, :read, :resource_type, :resource_id])
    |> maybe_generate_uuid()
    |> validate_required([:title, :category])
    |> validate_inclusion(:category, @categories)
    |> unique_constraint(:uuid)
  end

  defp maybe_generate_uuid(changeset) do
    if get_field(changeset, :uuid) do
      changeset
    else
      put_change(changeset, :uuid, Ecto.UUID.generate())
    end
  end
end
