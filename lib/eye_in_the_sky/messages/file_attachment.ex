defmodule EyeInTheSky.Messages.FileAttachment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "file_attachments" do
    field :uuid, :string
    field :filename, :string
    field :original_filename, :string
    field :content_type, :string
    field :size_bytes, :integer
    field :storage_path, :string
    field :upload_session_id, :string

    belongs_to :message, EyeInTheSky.Messages.Message,
      define_field: false,
      foreign_key: :message_id,
      type: :integer

    field :message_id, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [
      :uuid,
      :message_id,
      :filename,
      :original_filename,
      :content_type,
      :size_bytes,
      :storage_path,
      :upload_session_id,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :uuid,
      :message_id,
      :filename,
      :original_filename,
      :storage_path
    ])
    # 50MB max
    |> validate_number(:size_bytes, greater_than: 0, less_than_or_equal_to: 52_428_800)
  end

  @doc """
  Allowed file types for upload.
  """
  def allowed_content_types do
    [
      "image/jpeg",
      "image/png",
      "image/gif",
      "application/pdf",
      "text/plain",
      "application/zip",
      "application/x-tar",
      "application/gzip"
    ]
  end

  @doc """
  Check if a content type is allowed.
  """
  def allowed_content_type?(content_type) do
    content_type in allowed_content_types()
  end
end
