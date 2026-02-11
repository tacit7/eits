defmodule EyeInTheSkyWeb.Channels.ChannelMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "channel_members" do
    field :uuid, :string
    field :agent_id, :integer
    field :session_id, :integer
    field :role, :string, default: "member"
    field :joined_at, :utc_datetime
    field :last_read_at, :utc_datetime
    field :notifications, :string, default: "all"

    belongs_to :channel, EyeInTheSkyWeb.Channels.Channel,
      define_field: false,
      foreign_key: :channel_id,
      type: :integer

    field :channel_id, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(channel_member, attrs) do
    channel_member
    |> cast(attrs, [
      :channel_id,
      :agent_id,
      :session_id,
      :role,
      :joined_at,
      :last_read_at,
      :notifications,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([:channel_id, :agent_id, :session_id, :joined_at])
    |> validate_inclusion(:role, ["admin", "member"])
    |> validate_inclusion(:notifications, ["all", "mentions", "none"])
    |> unique_constraint([:channel_id, :session_id],
      name: :channel_members_channel_id_session_id_index
    )
  end
end
