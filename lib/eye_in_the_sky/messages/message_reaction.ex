defmodule EyeInTheSky.Messages.MessageReaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "message_reactions" do
    field :uuid, Ecto.UUID
    field :session_id, :integer
    field :emoji, :string

    belongs_to :message, EyeInTheSky.Messages.Message,
      define_field: false,
      foreign_key: :message_id,
      type: :integer

    field :message_id, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:message_id, :session_id, :emoji, :inserted_at])
    |> validate_required([:message_id, :session_id, :emoji])
    |> validate_length(:emoji, min: 1, max: 10)
    |> unique_constraint([:message_id, :session_id, :emoji],
      name: :message_reactions_message_id_session_id_emoji_index
    )
  end
end
