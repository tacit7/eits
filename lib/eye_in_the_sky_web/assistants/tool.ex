defmodule EyeInTheSkyWeb.Assistants.Tool do
  @moduledoc """
  Schema for the assistant tool catalog.
  Defines what tools exist, their metadata, and default approval requirements.
  Per-assistant access is controlled via assistants.tool_policy JSONB.
  Maps to the "assistant_tools" database table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "assistant_tools" do
    field :name, :string
    field :description, :string
    field :destructive, :boolean, default: false
    field :requires_approval_default, :boolean, default: false
    field :active, :boolean, default: true
    field :inserted_at, :naive_datetime
    field :updated_at, :naive_datetime
  end

  @doc false
  def changeset(tool, attrs) do
    tool
    |> cast(attrs, [:name, :description, :destructive, :requires_approval_default, :active])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:name)
  end
end
