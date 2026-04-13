defmodule EyeInTheSky.FileAttachments do
  @moduledoc """
  The FileAttachments context for managing file uploads in messages.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Messages.FileAttachment
  alias EyeInTheSky.Repo

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

  File is copied to disk only after validation passes. If the DB insert
  fails the copied file is removed, preventing orphaned files on disk.

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
  Deletes a file attachment: removes the DB record first, then the file.

  Deleting the DB record first ensures we never leave a dangling record
  pointing at a missing file. A leftover orphaned file on disk is preferable
  to a live record referencing a deleted file.
  """
  def delete_attachment(%FileAttachment{} = attachment) do
    with {:ok, deleted} <- Repo.delete(attachment) do
      File.rm(deleted.storage_path)
      {:ok, deleted}
    end
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
    ext = Path.extname(upload.filename)
    unique_filename = "#{Ecto.UUID.generate()}#{ext}"

    date_dir = Date.utc_today() |> Date.to_string()
    full_dir = Path.join([@upload_dir, date_dir])

    File.mkdir_p!(full_dir)

    storage_path = Path.join([full_dir, unique_filename])

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

    case %FileAttachment{}
         |> FileAttachment.changeset(attrs)
         |> Repo.insert() do
      {:ok, _} = ok ->
        ok

      {:error, _} = err ->
        # DB insert failed — clean up the copied file to prevent disk orphans.
        File.rm(storage_path)
        err
    end
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
    path = String.replace(attachment.storage_path, "priv/static", "")
    path
  end
end
