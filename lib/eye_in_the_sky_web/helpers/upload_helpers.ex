defmodule EyeInTheSkyWeb.Helpers.UploadHelpers do
  @moduledoc """
  Helpers for handling image uploads in LiveViews.
  """

  import Phoenix.LiveView, only: [consume_uploaded_entries: 3]

  alias EyeInTheSky.Claude.ContentBlock
  alias EyeInTheSky.Media.ImageProcessor

  def consume_agent_images(socket) do
    consume_uploaded_entries(socket, :agent_images, fn %{path: temp_path}, entry ->
      destination = agent_image_destination(entry.client_name)

      with :ok <- File.mkdir_p(Path.dirname(destination)),
           :ok <- File.cp(temp_path, destination) do
        {:ok, destination}
      else
        {:error, reason} ->
          require Logger

          Logger.warning(
            "consume_agent_images: failed to copy #{entry.client_name}: #{inspect(reason)}"
          )

          {:postpone, entry}
      end
    end)
  end

  def agent_image_destination(client_name) do
    base = Path.join([:code.priv_dir(:eye_in_the_sky), "static", "uploads", "agent"])
    date_dir = Date.utc_today() |> Date.to_string()
    filename = "#{Ecto.UUID.generate()}#{Path.extname(client_name)}"
    Path.join([base, date_dir, filename])
  end

  def append_image_paths(instructions, []), do: instructions

  def append_image_paths(instructions, image_paths) do
    paths = Enum.map_join(image_paths, "\n", fn p -> "- #{p}" end)
    "#{instructions}\n\nAttached images:\n#{paths}"
  end

  # Returns {file_infos, content_blocks} where:
  #   file_infos: [{storage_path, upload_entry, size_bytes}]
  #   content_blocks: processed ImageContentBlock list for agent routing
  # Saves images to disk and builds base64 content blocks in a single consume pass.
  def consume_and_persist_agent_images(socket) do
    results =
      consume_uploaded_entries(socket, :agent_images, fn %{path: temp_path}, entry ->
        destination = agent_image_destination(entry.client_name)

        with :ok <- File.mkdir_p(Path.dirname(destination)),
             {:ok, data} <- File.read(temp_path),
             :ok <- File.write(destination, data) do
          mime_type = entry.client_type || mime_from_ext(entry.client_name)
          content_block = ContentBlock.new_image(Base.encode64(data), mime_type)
          {:ok, {destination, entry, content_block, byte_size(data)}}
        else
          {:error, reason} ->
            require Logger

            Logger.warning(
              "consume_and_persist_agent_images: failed for #{entry.client_name}: #{inspect(reason)}"
            )

            {:postpone, entry}
        end
      end)

    file_infos = Enum.map(results, fn {path, entry, _block, size} -> {path, entry, size} end)

    blocks =
      results
      |> Enum.map(fn {_path, _entry, block, _size} -> block end)
      |> ImageProcessor.process_blocks()

    {file_infos, blocks}
  end

  def consume_agent_images_as_content_blocks(socket) do
    blocks =
      consume_uploaded_entries(socket, :agent_images, fn %{path: temp_path}, entry ->
        data = File.read!(temp_path)
        base64 = Base.encode64(data)
        mime_type = entry.client_type || mime_from_ext(entry.client_name)
        {:ok, ContentBlock.new_image(base64, mime_type)}
      end)

    ImageProcessor.process_blocks(blocks)
  end

  def mime_from_ext(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end
end
