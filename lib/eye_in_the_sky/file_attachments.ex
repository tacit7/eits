defmodule EyeInTheSky.FileAttachments do
  @moduledoc """
  The FileAttachments context for managing file uploads in messages.
  """

  alias EyeInTheSky.Messages.FileAttachment
  alias EyeInTheSky.Repo

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
end
