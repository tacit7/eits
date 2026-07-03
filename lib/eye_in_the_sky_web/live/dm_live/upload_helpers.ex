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

  # Process files dropped via Tauri native drag (paths are absolute OS paths).
  # Copies each file to the same upload destination as browser uploads and
  # returns the same shape of file_data map so message_handlers can treat them
  # identically.
  def consume_tauri_files(socket) do
    paths = socket.assigns[:tauri_dropped_files] || []

    results =
      Enum.flat_map(paths, fn path ->
        case File.stat(path) do
          {:ok, %{size: size}} ->
            client_name = Path.basename(path)
            destination = upload_destination(client_name)
            File.mkdir_p!(Path.dirname(destination))

            case File.cp(path, destination) do
              :ok ->
                [
                  %{
                    storage_path: destination,
                    filename: Path.basename(destination),
                    original_filename: client_name,
                    content_type: MIME.from_path(client_name),
                    size_bytes: size
                  }
                ]

              {:error, reason} ->
                Logger.warning("Failed to copy Tauri dropped file #{path}: #{inspect(reason)}")
                []
            end

          {:error, reason} ->
            Logger.warning("Cannot stat Tauri dropped file #{path}: #{inspect(reason)}")
            []
        end
      end)

    results
  end

  def build_message_body(body, []), do: body

  def build_message_body(body, uploaded_files) do
    file_list =
      Enum.map_join(uploaded_files, "\n", fn file_data ->
        "- #{file_data.storage_path} (#{file_data.original_filename})"
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

  def mime_from_ext(filename), do: MIME.from_path(filename)
end
