defmodule EyeInTheSky.FileAttachments do
  @moduledoc """
  The FileAttachments context for managing file uploads in messages.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Messages.FileAttachment

  @upload_dir "priv/static/uploads/attachments"
  # 50MB in bytes
  @max_file_size 52_428_800

  @doc """
  Returns the list of file attachments for a message.
  """
  def list_attachments_for_message(message_id) do
    FileAttachment
    |> where([a], a.message_id == ^message_id)
    |> order_by([a], asc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single file attachment.

  Raises `Ecto.NoResultsError` if the FileAttachment does not exist.
  """
  def get_attachment!(id) do
    Repo.get!(FileAttachment, id)
  end

  @doc """
  Gets a file attachment, returns {:ok, attachment} or {:error, :not_found}.
  """
  def get_attachment(id) do
    case Repo.get(FileAttachment, id) do
      nil -> {:error, :not_found}
      attachment -> {:ok, attachment}
    end
  end

  @doc """
  Uploads a file and creates a file attachment record.

  ## Parameters
    - message_id: The message to attach the file to
    - upload: A map with :path and :filename keys
    - session_id: The session uploading the file

  ## Returns
    - {:ok, attachment} on success
    - {:error, reason} on failure
  """
  def upload_file(message_id, upload, session_id) do
    with :ok <- validate_upload(upload),
         {:ok, storage_path} <- save_file(upload),
         {:ok, attachment} <- create_attachment(message_id, upload, storage_path, session_id) do
      {:ok, attachment}
    end
  end

  @doc """
  Deletes a file attachment and removes the file from storage.
  """
  def delete_attachment(%FileAttachment{} = attachment) do
    # Delete the file from storage
    File.rm(attachment.storage_path)

    # Delete the database record
    Repo.delete(attachment)
  end

  @doc """
  Returns the maximum allowed file size in bytes.
  """
  def max_file_size, do: @max_file_size

  @doc """
  Returns the upload directory path.
  """
  def upload_dir, do: @upload_dir

  # Private functions

  defp validate_upload(upload) do
    cond do
      not Map.has_key?(upload, :path) ->
        {:error, :missing_path}

      not Map.has_key?(upload, :filename) ->
        {:error, :missing_filename}

      not File.exists?(upload.path) ->
        {:error, :file_not_found}

      get_file_size(upload.path) > @max_file_size ->
        {:error, :file_too_large}

      not FileAttachment.allowed_content_type?(upload.content_type) ->
        {:error, :invalid_file_type}

      true ->
        :ok
    end
  end

  defp get_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp save_file(upload) do
    # Generate unique filename
    ext = Path.extname(upload.filename)
    unique_filename = "#{Ecto.UUID.generate()}#{ext}"

    # Create date-based subdirectory
    date_dir = Date.utc_today() |> Date.to_string()
    full_dir = Path.join([@upload_dir, date_dir])

    # Ensure directory exists
    File.mkdir_p!(full_dir)

    # Build storage path
    storage_path = Path.join([full_dir, unique_filename])

    # Copy file to storage
    case File.cp(upload.path, storage_path) do
      :ok -> {:ok, storage_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_attachment(message_id, upload, storage_path, session_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    file_size = get_file_size(upload.path)

    attrs = %{
      message_id: message_id,
      filename: Path.basename(storage_path),
      original_filename: upload.filename,
      content_type: upload.content_type,
      size_bytes: file_size,
      storage_path: storage_path,
      upload_session_id: session_id,
      inserted_at: now,
      updated_at: now
    }

    %FileAttachment{}
    |> FileAttachment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a file attachment record from a map of attributes.
  """
  def create_attachment(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      attrs
      |> Map.put_new(:uuid, Ecto.UUID.generate())
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)

    %FileAttachment{}
    |> FileAttachment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a public URL for accessing an uploaded file.
  """
  def get_public_url(%FileAttachment{} = attachment) do
    # Convert storage path to public URL
    # e.g., priv/static/uploads/attachments/2025-12-02/abc.pdf
    #    -> /uploads/attachments/2025-12-02/abc.pdf
    path = String.replace(attachment.storage_path, "priv/static", "")
    path
  end
end
