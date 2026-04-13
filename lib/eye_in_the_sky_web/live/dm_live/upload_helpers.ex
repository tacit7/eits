defmodule EyeInTheSkyWeb.DmLive.UploadHelpers do
  @moduledoc false

  alias EyeInTheSky.FileAttachments

  require Logger

  def consume_uploaded_files(socket) do
    Phoenix.LiveView.consume_uploaded_entries(socket, :files, fn %{path: temp_path}, entry ->
      destination = upload_destination(entry.client_name)

      File.mkdir_p!(Path.dirname(destination))
      File.cp!(temp_path, destination)

      {:ok,
       %{
         storage_path: destination,
         filename: Path.basename(destination),
         original_filename: entry.client_name,
         content_type: MIME.from_path(entry.client_name),
         size_bytes: entry.client_size
       }}
    end)
  end

  def build_message_body(body, []), do: body

  def build_message_body(body, uploaded_files) do
    file_list =
      Enum.map_join(uploaded_files, "\n", fn file_data ->
        relative = relative_upload_path(file_data.storage_path)
        "- #{relative} (#{file_data.original_filename})"
      end)

    "#{body}\n\nAttached files:\n#{file_list}"
  end

  def persist_upload_attachments(uploaded_files, message_id) do
    Enum.each(uploaded_files, fn file_data ->
      case FileAttachments.create_attachment(Map.put(file_data, :message_id, message_id)) do
        {:ok, _attachment} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to persist attachment for message_id=#{message_id}: #{inspect(reason)}"
          )
      end
    end)
  end

  defp upload_destination(client_name) do
    base_upload_dir = Path.join([:code.priv_dir(:eye_in_the_sky), "static", "uploads", "dm"])
    date_dir = Date.utc_today() |> Date.to_string()
    filename = "#{Ecto.UUID.generate()}#{Path.extname(client_name)}"
    Path.join([base_upload_dir, date_dir, filename])
  end

  defp relative_upload_path(abs_path) do
    priv_static = Path.join(:code.priv_dir(:eye_in_the_sky), "static")

    case String.split(abs_path, priv_static, parts: 2) do
      [_, relative] -> relative
      _ -> Path.basename(abs_path)
    end
  end

  def mime_from_ext(filename), do: MIME.from_path(filename)
end
