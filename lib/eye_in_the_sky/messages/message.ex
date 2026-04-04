defmodule EyeInTheSky.Messages.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "messages" do
    field :uuid, Ecto.UUID
    field :sender_role, :string
    field :recipient_role, :string
    field :provider, :string
    field :provider_session_id, :string
    field :direction, :string
    field :body, :string
    field :status, :string, default: "sent"
    field :metadata, :map
    field :channel_message_number, :integer
    field :thread_reply_count, :integer, default: 0
    field :last_thread_reply_at, :utc_datetime

    belongs_to :project, EyeInTheSky.Projects.Project, type: :integer

    belongs_to :session, EyeInTheSky.Sessions.Session,
      define_field: false,
      foreign_key: :session_id,
      type: :integer

    belongs_to :channel, EyeInTheSky.Channels.Channel,
      define_field: false,
      foreign_key: :channel_id,
      type: :integer

    belongs_to :parent_message, __MODULE__,
      define_field: false,
      foreign_key: :parent_message_id,
      type: :integer

    has_many :thread_replies, __MODULE__, foreign_key: :parent_message_id
    has_many :reactions, EyeInTheSky.Messages.MessageReaction
    has_many :attachments, EyeInTheSky.Messages.FileAttachment

    field :failure_reason, :string
    field :source_uuid, Ecto.UUID
    field :session_id, :integer
    field :channel_id, :integer
    field :parent_message_id, :integer
    field :from_session_id, :integer
    field :to_session_id, :integer
    field :inserted_at, :utc_datetime
    field :updated_at, :utc_datetime
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :uuid,
      :project_id,
      :session_id,
      :channel_id,
      :parent_message_id,
      :sender_role,
      :recipient_role,
      :provider,
      :provider_session_id,
      :direction,
      :body,
      :status,
      :failure_reason,
      :metadata,
      :source_uuid,
      :from_session_id,
      :to_session_id,
      :channel_message_number,
      :thread_reply_count,
      :last_thread_reply_at,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([:sender_role, :direction, :body])
    |> validate_inclusion(:direction, ["inbound", "outbound"])
    |> validate_inclusion(:status, ["sent", "delivered", "failed", "pending", "processing"])
    |> unique_constraint(:source_uuid, name: "messages_source_uuid_index")
  end
end
