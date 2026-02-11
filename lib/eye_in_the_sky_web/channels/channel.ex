defmodule EyeInTheSkyWeb.Channels.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "channels" do
    field :uuid, :string
    field :name, :string
    field :description, :string
    field :channel_type, :string, default: "public"
    field :created_by_session_id, :string
    field :archived_at, :utc_datetime

    belongs_to :project, EyeInTheSkyWeb.Projects.Project, type: :integer
    has_many :channel_members, EyeInTheSkyWeb.Channels.ChannelMember
    has_many :messages, EyeInTheSkyWeb.Messages.Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :uuid,
      :name,
      :description,
      :channel_type,
      :project_id,
      :created_by_session_id,
      :archived_at,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([:name, :channel_type])
    |> validate_inclusion(:channel_type, ["public", "private", "dm"])
    |> unique_constraint([:project_id, :name], name: :channels_project_id_name_index)
  end

  @doc """
  Generates a default channel ID based on project ID and channel name.
  Format: "proj-{project_id}-{slugified_name}"
  """
  def generate_id(project_id, name) do
    slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
    "proj-#{project_id}-#{slug}"
  end
end
