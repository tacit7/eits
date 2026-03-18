defmodule EyeInTheSkyWeb.Checkpoints.Checkpoint do
  @moduledoc """
  Schema for session checkpoints.
  Maps to the "session_checkpoints" database table.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "session_checkpoints" do
    field :session_id, :integer
    field :name, :string
    field :description, :string
    field :message_index, :integer, default: 0
    field :git_stash_ref, :string
    field :metadata, :map, default: %{}
    field :inserted_at, :utc_datetime
  end

  @doc false
  def changeset(checkpoint, attrs) do
    checkpoint
    |> cast(attrs, [
      :session_id,
      :name,
      :description,
      :message_index,
      :git_stash_ref,
      :metadata,
      :inserted_at
    ])
    |> validate_required([:session_id, :message_index])
  end
end
