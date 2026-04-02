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
      File.mkdir_p!(Path.dirname(destination))
      File.cp!(temp_path, destination)
      {:ok, destination}
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
