defmodule EyeInTheSky.FileAttachments do
  @moduledoc """
  The FileAttachments context for managing file uploads in messages.
  """

  alias EyeInTheSky.Messages.FileAttachment
  alias EyeInTheSky.Repo
  require Logger

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
  Deletes a file attachment and removes the physical file from disk.
  Returns :ok on success, {:error, reason} on failure.
  """
  def delete_attachment(%FileAttachment{} = attachment) do
    # Delete the physical file first
    case File.rm(attachment.storage_path) do
      :ok ->
        # File deleted successfully, now delete the DB record
        case Repo.delete(attachment) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, {:db_delete_failed, reason}}
        end

      {:error, :enoent} ->
        # File doesn't exist, but we can still delete the DB record
        case Repo.delete(attachment) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, {:db_delete_failed, reason}}
        end

      {:error, reason} ->
        Logger.warning(
          "Failed to delete attachment file #{attachment.storage_path}: #{inspect(reason)}"
        )

        {:error, {:file_delete_failed, reason}}
    end
  end

  def delete_attachment(attachment_id) when is_integer(attachment_id) do
    case Repo.get(FileAttachment, attachment_id) do
      nil -> {:error, :not_found}
      attachment -> delete_attachment(attachment)
    end
  end
end
